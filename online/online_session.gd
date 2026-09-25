class_name RPSOnlineSession
extends Node

signal connected(user: Dictionary)
signal disconnected
signal status_changed(message: String)
signal friend_list_updated(payload: Dictionary)
signal invite_received(payload: Dictionary)
signal match_found(payload: Dictionary)
signal match_resumed(payload: Dictionary)
signal match_setup_ready(payload: Dictionary)
signal opponent_ready(turn_number: int)
signal opponent_disconnected(reconnect_seconds: int)
signal opponent_reconnected
signal turn_reveal(payload: Dictionary)
signal public_action_received(payload: Dictionary)
signal hidden_action_accepted(payload: Dictionary)
signal hidden_state_action(payload: Dictionary)
signal turn_ready_accepted(turn_number: int)
signal combat_start(payload: Dictionary)
signal turn_start(payload: Dictionary)
signal state_desync(payload: Dictionary)
signal game_over_commit(payload: Dictionary)
signal transport_interrupted
signal transport_restored
signal server_error(message: String)

const CONFIG_PATH := "user://rps_online.cfg"
const FIXED_SERVER_URL := "https://game.lingonikacademy.ir"
const LOBBY_POLL_SECONDS := 1.5
const MATCH_POLL_SECONDS := 0.20
const MAX_POLL_FAILURES := 60

var server_url: String = FIXED_SERVER_URL
var username: String = "Player"
var token: String = ""
var user: Dictionary = {}
var current_match: Dictionary = {}

var _connected: bool = false
var _auth_in_flight: bool = false
var _poll_in_flight: bool = false
var _command_in_flight: bool = false
var _poll_wait: float = 0.0
var _poll_failures: int = 0
var _command_queue: Array[Dictionary] = []
var _active_command: Dictionary = {}

# Reliable HTTPS transport state.
var _last_event_id: int = 0
var _server_epoch: String = ""
var _command_sequence: int = 0
var _command_session_nonce: String = ""

var _auth_http: HTTPRequest
var _poll_http: HTTPRequest
var _command_http: HTTPRequest

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_load_config()
	server_url = FIXED_SERVER_URL
	_command_session_nonce = "%s-%s" % [
		str(Time.get_ticks_usec()),
		str(randi())
	]

	_auth_http = HTTPRequest.new()
	_auth_http.name = "OnlineAuthHTTP"
	_auth_http.timeout = 12.0
	add_child(_auth_http)
	_auth_http.request_completed.connect(_on_auth_completed)

	_poll_http = HTTPRequest.new()
	_poll_http.name = "OnlinePollHTTP"
	_poll_http.timeout = 10.0
	add_child(_poll_http)
	_poll_http.request_completed.connect(_on_poll_completed)

	_command_http = HTTPRequest.new()
	_command_http.name = "OnlineCommandHTTP"
	_command_http.timeout = 10.0
	add_child(_command_http)
	_command_http.request_completed.connect(_on_command_completed)

func _process(delta: float) -> void:
	if not _connected:
		return

	if not _command_in_flight and not _command_queue.is_empty():
		_start_next_command()

	_poll_wait -= delta
	if _poll_wait <= 0.0 and not _poll_in_flight:
		_poll_wait = MATCH_POLL_SECONDS if not current_match.is_empty() else LOBBY_POLL_SECONDS
		_start_poll()

func configure(new_username: String) -> void:
	var previous_username := username
	server_url = FIXED_SERVER_URL
	username = new_username.strip_edges()
	if username.length() < 2:
		username = "Player"

	if (
		not previous_username.is_empty()
		and username.to_lower() != previous_username.to_lower()
	):
		token = ""
		user.clear()
		current_match.clear()

	_save_config()


func connect_server(new_username: String = "") -> void:
	if _auth_in_flight:
		return
	if not new_username.is_empty():
		configure(new_username)
	else:
		server_url = FIXED_SERVER_URL

	_connected = false
	_poll_failures = 0
	_command_queue.clear()
	_active_command.clear()
	status_changed.emit("Connecting over HTTPS...")

	var body := JSON.stringify({
		"token": token,
		"username": username,
		# Connecting from the Online Lobby means "I want a fresh lobby".
		# The server must close any abandoned room from an older play session
		# instead of auto-resuming it.
		"fresh_lobby": true
	})
	var headers := PackedStringArray(["Content-Type: application/json"])
	_auth_in_flight = true
	var err := _auth_http.request(
		_api_url("/api/connect"),
		headers,
		HTTPClient.METHOD_POST,
		body
	)
	if err != OK:
		_auth_in_flight = false
		status_changed.emit("HTTPS connect failed: %s" % err)
		disconnected.emit()

func disconnect_server() -> void:
	if _connected and not token.is_empty():
		var temp := HTTPRequest.new()
		get_tree().root.add_child(temp)
		temp.timeout = 4.0
		temp.request_completed.connect(func(_r, _c, _h, _b): temp.queue_free())
		temp.request(
			_api_url("/api/disconnect"),
			_auth_headers(),
			HTTPClient.METHOD_POST,
			"{}"
		)
	_connected = false
	_poll_in_flight = false
	_command_in_flight = false
	_command_queue.clear()
	status_changed.emit("Disconnected")
	disconnected.emit()

func is_connected_to_server() -> bool:
	return _connected and not token.is_empty() and not user.is_empty()

func request_friend_list() -> void:
	_send({"type": "friend_list"})

func add_friend(friend_code: String) -> void:
	_send({"type": "friend_request", "friend_code": friend_code.strip_edges().to_upper()})

func accept_friend(user_id: int) -> void:
	_send({"type": "friend_accept", "user_id": user_id})

func join_matchmaking(mode: String) -> void:
	# FIND NORMAL/RUSH always means a brand-new room. Clear any stale local
	# match payload immediately; the server independently closes the old room.
	current_match.clear()
	_poll_wait = 0.0
	_send({"type": "matchmaking_join", "mode": mode, "setup": {}, "protocol_version": 6})

func cancel_matchmaking() -> void:
	_send({"type": "matchmaking_cancel"})


func leave_current_match() -> void:
	# Used when the player intentionally leaves an online room. Clear local
	# state first so no stale room can affect the lobby while the command is
	# traveling over HTTPS.
	current_match.clear()
	_poll_wait = 0.0
	if _connected:
		_send({"type": "match_leave"})


func invite_friend(user_id: int, mode: String) -> void:
	_send({"type": "match_invite", "user_id": user_id, "mode": mode, "setup": {}})

func accept_match_invite(invite_id: String) -> void:
	_send({"type": "match_invite_accept", "invite_id": invite_id, "setup": {}})


func submit_match_setup(stage: String, setup: Dictionary) -> void:
	_send({
		"type": "match_setup",
		"stage": stage,
		"setup": setup
	})

func queue_hidden_action(action: Dictionary, turn_number: int) -> void:
	_send({"type": "hidden_action", "turn": turn_number, "action": action})

func send_public_action(action: Dictionary, turn_number: int = -1) -> void:
	_send({"type": "public_action", "turn": turn_number, "action": action})

func ready_turn(turn_number: int, keep_ids: Array) -> void:
	_send({"type": "turn_ready", "turn": turn_number, "keep_ids": keep_ids})

func reveal_ready(turn_number: int) -> void:
	_send({"type": "reveal_ready", "turn": turn_number})

func complete_turn(
	turn_number: int,
	state_digest: String,
	game_over: bool = false,
	winner_seat: int = 0
) -> void:
	_send({
		"type": "turn_complete",
		"turn": turn_number,
		"state_digest": state_digest,
		"game_over": game_over,
		"winner_seat": winner_seat
	})

func report_client_fault(turn_number: int, reason: String) -> void:
	_send({"type": "client_fault", "turn": turn_number, "reason": reason})

func report_match_end(winner_seat: int) -> void:
	_send({"type": "match_end", "winner_seat": winner_seat})

func _send(payload: Dictionary) -> void:
	if not _connected:
		status_changed.emit("Connect first")
		return

	var queued := payload.duplicate(true)
	if not queued.has("client_command_id"):
		_command_sequence += 1
		queued["client_command_id"] = "%s-%s" % [
			_command_session_nonce,
			str(_command_sequence)
		]

	_command_queue.append(queued)

func _start_next_command() -> void:
	if _command_queue.is_empty() or not _connected:
		return
	_active_command = _command_queue.pop_front()
	_command_in_flight = true
	var err := _command_http.request(
		_api_url("/api/message"),
		_auth_headers(),
		HTTPClient.METHOD_POST,
		JSON.stringify(_active_command)
	)
	if err != OK:
		_command_in_flight = false
		_command_queue.push_front(_active_command)
		_active_command = {}
		status_changed.emit("Command send failed; retrying...")

func _start_poll() -> void:
	if not _connected or token.is_empty():
		return
	_poll_in_flight = true
	var poll_path := "/api/events?after=%s" % _last_event_id
	var err := _poll_http.request(
		_api_url(poll_path),
		_auth_headers(),
		HTTPClient.METHOD_GET
	)
	if err != OK:
		_poll_in_flight = false
		_register_poll_failure("Poll request failed: %s" % err)

func _on_auth_completed(
	result: int,
	response_code: int,
	_headers: PackedStringArray,
	body: PackedByteArray
) -> void:
	_auth_in_flight = false
	if result != HTTPRequest.RESULT_SUCCESS or response_code != 200:
		status_changed.emit("Server connection failed (HTTP %s)" % response_code)
		disconnected.emit()
		return

	var payload = JSON.parse_string(body.get_string_from_utf8())
	if not (payload is Dictionary) or not bool(payload.get("ok", false)):
		status_changed.emit("Invalid server response")
		disconnected.emit()
		return

	token = String(payload.get("token", ""))
	user = payload.get("user", {}) as Dictionary
	_connected = not token.is_empty() and not user.is_empty()
	_poll_failures = 0
	_poll_wait = 0.0
	_last_event_id = int(payload.get("event_cursor", 0))
	_server_epoch = String(payload.get("server_epoch", ""))
	_save_config()

	if not _connected:
		status_changed.emit("Login failed")
		disconnected.emit()
		return

	status_changed.emit("Online via HTTPS")
	connected.emit(user)
	_dispatch_events(payload.get("events", []))

func _on_poll_completed(
	result: int,
	response_code: int,
	_headers: PackedStringArray,
	body: PackedByteArray
) -> void:
	_poll_in_flight = false
	if not _connected:
		return
	if result != HTTPRequest.RESULT_SUCCESS or response_code != 200:
		_register_poll_failure("Server poll failed (HTTP %s)" % response_code)
		return

	var payload = JSON.parse_string(body.get_string_from_utf8())
	if not (payload is Dictionary) or not bool(payload.get("ok", false)):
		_register_poll_failure("Invalid polling response")
		return

	var response_epoch := String(payload.get("server_epoch", ""))
	if not _server_epoch.is_empty() and not response_epoch.is_empty() and response_epoch != _server_epoch:
		state_desync.emit({
			"type": "state_desync",
			"match_id": String(current_match.get("match_id", "")),
			"turn": int(current_match.get("turn", 0)),
			"reason": "server_restarted"
		})
		_server_epoch = response_epoch
		return
	var incoming_events: Array = payload.get("events", []) as Array
	var has_terminal_event := false
	for raw_event: Variant in incoming_events:
		if raw_event is Dictionary:
			var terminal_type := String((raw_event as Dictionary).get("type", ""))
			if terminal_type in ["game_over_commit", "match_closed", "state_desync"]:
				has_terminal_event = true
				break
	if (
		not current_match.is_empty()
		and not bool(payload.get("match_active", true))
		and not has_terminal_event
	):
		state_desync.emit({
			"type": "state_desync",
			"match_id": String(current_match.get("match_id", "")),
			"turn": int(current_match.get("turn", 0)),
			"reason": "server_room_missing"
		})
		return

	var had_failures := _poll_failures > 0
	_poll_failures = 0
	if had_failures:
		transport_restored.emit()
		status_changed.emit("Connection restored")
	_dispatch_reliable_events(incoming_events)

func _on_command_completed(
	result: int,
	response_code: int,
	_headers: PackedStringArray,
	_body: PackedByteArray
) -> void:
	_command_in_flight = false
	if not _connected:
		_active_command = {}
		return

	if result != HTTPRequest.RESULT_SUCCESS or response_code != 200:
		if not _active_command.is_empty():
			_command_queue.push_front(_active_command)
		status_changed.emit("Command failed; retrying...")
		_active_command = {}
		return

	_active_command = {}
	# Poll immediately after a successful command so matchmaking/actions feel
	# responsive even though the transport is plain HTTPS.
	_poll_wait = 0.0

func _register_poll_failure(message: String) -> void:
	_poll_failures += 1
	if _poll_failures == 1:
		transport_interrupted.emit()
	if _poll_failures >= 3:
		status_changed.emit("Connection unstable; retrying...")

	if not current_match.is_empty():
		_poll_wait = 1.0
		return

	if _poll_failures >= MAX_POLL_FAILURES:
		_connected = false
		status_changed.emit(message)
		disconnected.emit()


func _dispatch_reliable_events(value) -> void:
	if not (value is Array):
		return

	for item in value:
		if not (item is Dictionary):
			continue

		var payload := item as Dictionary
		var event_id := int(payload.get("_http_event_id", 0))

		# The same response can safely be delivered twice after a timeout.
		if event_id > 0 and event_id <= _last_event_id:
			continue

		_handle_packet(payload)

		# Advance only after the event reached the game-side dispatcher.
		if event_id > _last_event_id:
			_last_event_id = event_id


func _dispatch_events(value) -> void:
	if not (value is Array):
		return
	for item in value:
		if item is Dictionary:
			_handle_packet(item as Dictionary)

func _handle_packet(payload: Dictionary) -> void:
	var message_type := String(payload.get("type", ""))
	var packet_match_id := String(payload.get("match_id", ""))

	# Durable HTTPS events may arrive after a room was intentionally closed.
	# Never let an event from an old room mutate the new/current match.
	var room_scoped_types := [
		"match_setup_waiting",
		"match_setup_ready",
		"opponent_ready",
		"opponent_disconnected",
		"opponent_reconnected",
		"turn_reveal",
		"public_action",
		"hidden_action_ok",
		"hidden_action_accepted",
		"hidden_state_action",
		"turn_ready_accepted",
		"combat_start",
		"turn_start",
		"state_desync",
		"game_over_commit",
	]
	if (
		message_type in room_scoped_types
		and not packet_match_id.is_empty()
		and (
			current_match.is_empty()
			or packet_match_id != String(current_match.get("match_id", ""))
		)
	):
		return

	match message_type:
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
		"match_setup_waiting":
			var stage := String(payload.get("stage", "setup"))
			status_changed.emit("Waiting for opponent %s..." % stage)
		"match_setup_ready":
			var merged := current_match.duplicate(true)
			for key in payload.keys():
				merged[key] = payload[key]
			current_match = merged
			match_setup_ready.emit(current_match)
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
		"hidden_action_accepted":
			hidden_action_accepted.emit(payload)
		"hidden_state_action":
			hidden_state_action.emit(payload)
		"turn_ready_accepted":
			turn_ready_accepted.emit(int(payload.get("turn", 0)))
		"combat_start":
			combat_start.emit(payload)
		"turn_start":
			turn_start.emit(payload)
		"state_desync":
			state_desync.emit(payload)
		"game_over_commit":
			game_over_commit.emit(payload)
		"match_closed":
			var closed_match_id := String(payload.get("match_id", ""))
			var active_match_id := String(current_match.get("match_id", ""))
			if (
				active_match_id.is_empty()
				or closed_match_id.is_empty()
				or closed_match_id == active_match_id
			):
				current_match.clear()
				status_changed.emit("Match closed")
		"error":
			var message := String(payload.get("message", "Server error"))
			status_changed.emit(message)
			server_error.emit(message)
		"hidden_action_ok", "pong":
			pass

func _api_url(path: String) -> String:
	return "%s%s" % [_normalize_base_url(server_url), path]

func _auth_headers() -> PackedStringArray:
	return PackedStringArray([
		"Content-Type: application/json",
		"X-RPS-Token: %s" % token
	])

func _normalize_base_url(value: String) -> String:
	var result := value.strip_edges()
	if result.begins_with("wss://"):
		result = "https://" + result.substr(6)
	elif result.begins_with("ws://"):
		result = "http://" + result.substr(5)
	elif not result.begins_with("http://") and not result.begins_with("https://"):
		result = "https://" + result

	while result.ends_with("/") and result.length() > 0:
		result = result.substr(0, result.length() - 1)
	if result.ends_with("/ws"):
		result = result.substr(0, result.length() - 3)
	while result.ends_with("/") and result.length() > 0:
		result = result.substr(0, result.length() - 1)

	# Migrate the temporary Cloudflare test URL to the production subdomain.
	if "trycloudflare.com" in result:
		result = "https://game.lingonikacademy.ir"
	return result

func _load_config() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(CONFIG_PATH) != OK:
		return
	server_url = FIXED_SERVER_URL
	username = String(cfg.get_value("online", "username", username))
	token = String(cfg.get_value("online", "token", token))

func _save_config() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("online", "username", username)
	cfg.set_value("online", "token", token)
	cfg.save(CONFIG_PATH)
