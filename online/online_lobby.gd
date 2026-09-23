class_name RPSOnlineLobby
extends CanvasLayer

signal close_requested

var session: RPSOnlineSession
var connection_label: Label
var status_label: Label
var identity_label: Label
var connect_button: Button
var username_edit: LineEdit
var friend_code_edit: LineEdit
var friend_list: ItemList
var request_list: ItemList
var invite_label: Label
var accept_invite_button: Button
var pending_invite: Dictionary = {}
var friends_payload: Dictionary = {}


func _ready() -> void:
	layer = 250
	process_mode = Node.PROCESS_MODE_ALWAYS
	session = get_node_or_null("/root/OnlineSession")
	_build_ui()
	_bind_session()
	_sync_from_session()


func _build_ui() -> void:
	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.025, 0.04, 0.94)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(760, 620)
	center.add_child(panel)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 10)
	panel.add_child(root)

	var title := Label.new()
	title.text = "RPS DUEL ONLINE"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 28)
	root.add_child(title)

	connection_label = Label.new()
	connection_label.text = "● OFFLINE"
	connection_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	connection_label.add_theme_font_size_override("font_size", 24)
	connection_label.add_theme_color_override(
		"font_color",
		Color(1.0, 0.32, 0.32)
	)
	root.add_child(connection_label)

	status_label = Label.new()
	status_label.text = "Enter your name to connect"
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status_label.add_theme_font_size_override("font_size", 18)
	root.add_child(status_label)

	identity_label = Label.new()
	identity_label.text = "Username: -  |  Friend Code: -"
	identity_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	identity_label.add_theme_font_size_override("font_size", 18)
	root.add_child(identity_label)

	var name_row := HBoxContainer.new()
	root.add_child(name_row)

	username_edit = LineEdit.new()
	username_edit.placeholder_text = "Your name"
	username_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	username_edit.custom_minimum_size.x = 380
	username_edit.text_submitted.connect(
		func(_value: String): _on_connect_pressed()
	)
	name_row.add_child(username_edit)

	connect_button = Button.new()
	connect_button.text = "CONNECT"
	connect_button.custom_minimum_size.x = 160
	connect_button.pressed.connect(_on_connect_pressed)
	name_row.add_child(connect_button)

	var server_note := Label.new()
	server_note.text = "Server: game.lingonikacademy.ir"
	server_note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	server_note.modulate = Color(1.0, 1.0, 1.0, 0.55)
	server_note.add_theme_font_size_override("font_size", 14)
	root.add_child(server_note)

	var sep1 := HSeparator.new()
	root.add_child(sep1)

	var play_title := Label.new()
	play_title.text = "PLAY ONLINE"
	play_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	play_title.add_theme_font_size_override("font_size", 20)
	root.add_child(play_title)

	var play_row := HBoxContainer.new()
	play_row.alignment = BoxContainer.ALIGNMENT_CENTER
	root.add_child(play_row)

	var normal_button := Button.new()
	normal_button.text = "FIND NORMAL"
	normal_button.custom_minimum_size = Vector2(210, 54)
	normal_button.pressed.connect(func(): _join_queue("normal"))
	play_row.add_child(normal_button)

	var rush_button := Button.new()
	rush_button.text = "FIND RUSH"
	rush_button.custom_minimum_size = Vector2(210, 54)
	rush_button.pressed.connect(func(): _join_queue("rush"))
	play_row.add_child(rush_button)

	var cancel_queue := Button.new()
	cancel_queue.text = "CANCEL"
	cancel_queue.custom_minimum_size = Vector2(130, 54)
	cancel_queue.pressed.connect(_on_cancel_matchmaking)
	play_row.add_child(cancel_queue)

	var setup_note := Label.new()
	setup_note.text = "Deck, Hero and Hero position are selected after an opponent is found."
	setup_note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	setup_note.modulate = Color(1.0, 1.0, 1.0, 0.72)
	root.add_child(setup_note)

	var sep2 := HSeparator.new()
	root.add_child(sep2)

	var friend_row := HBoxContainer.new()
	root.add_child(friend_row)
	friend_code_edit = LineEdit.new()
	friend_code_edit.placeholder_text = "Friend code"
	friend_code_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	friend_row.add_child(friend_code_edit)

	var add_friend_button := Button.new()
	add_friend_button.text = "ADD FRIEND"
	add_friend_button.pressed.connect(_on_add_friend)
	friend_row.add_child(add_friend_button)

	var refresh_button := Button.new()
	refresh_button.text = "REFRESH"
	refresh_button.pressed.connect(_on_refresh_friends)
	friend_row.add_child(refresh_button)

	var lists_row := HBoxContainer.new()
	lists_row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(lists_row)

	var friends_box := VBoxContainer.new()
	friends_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lists_row.add_child(friends_box)

	var fl := Label.new()
	fl.text = "Friends"
	friends_box.add_child(fl)

	friend_list = ItemList.new()
	friend_list.custom_minimum_size = Vector2(0, 150)
	friend_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	friends_box.add_child(friend_list)

	var invite_row := HBoxContainer.new()
	friends_box.add_child(invite_row)

	var invite_normal := Button.new()
	invite_normal.text = "INVITE NORMAL"
	invite_normal.pressed.connect(func(): _invite_selected("normal"))
	invite_row.add_child(invite_normal)

	var invite_rush := Button.new()
	invite_rush.text = "INVITE RUSH"
	invite_rush.pressed.connect(func(): _invite_selected("rush"))
	invite_row.add_child(invite_rush)

	var requests_box := VBoxContainer.new()
	requests_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lists_row.add_child(requests_box)

	var rl := Label.new()
	rl.text = "Friend Requests"
	requests_box.add_child(rl)

	request_list = ItemList.new()
	request_list.custom_minimum_size = Vector2(0, 150)
	request_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	requests_box.add_child(request_list)

	var accept_friend_button := Button.new()
	accept_friend_button.text = "ACCEPT SELECTED"
	accept_friend_button.pressed.connect(_accept_selected_request)
	requests_box.add_child(accept_friend_button)

	invite_label = Label.new()
	invite_label.text = ""
	invite_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(invite_label)

	accept_invite_button = Button.new()
	accept_invite_button.text = "ACCEPT MATCH INVITE"
	accept_invite_button.visible = false
	accept_invite_button.pressed.connect(_accept_pending_invite)
	root.add_child(accept_invite_button)

	var close_button := Button.new()
	close_button.text = "BACK"
	close_button.pressed.connect(func(): close_requested.emit())
	root.add_child(close_button)


func _bind_session() -> void:
	if session == null:
		status_label.text = "OnlineSession autoload missing"
		return
	if session.has_signal("connected"):
		session.connected.connect(_on_connected)
		session.disconnected.connect(_on_disconnected)
		session.status_changed.connect(_on_status)
		session.friend_list_updated.connect(_on_friend_list)
		session.invite_received.connect(_on_invite)


func _sync_from_session() -> void:
	if session == null:
		return
	username_edit.text = (
		""
		if String(session.username) == "Player"
		else String(session.username)
	)
	if session.is_connected_to_server():
		_on_connected(session.user)
		session.request_friend_list()


func _on_connect_pressed() -> void:
	if session == null:
		return

	if session.is_connected_to_server():
		connection_label.text = "● DISCONNECTING..."
		connection_label.add_theme_color_override(
			"font_color",
			Color(1.0, 0.72, 0.22)
		)
		connect_button.disabled = true
		session.disconnect_server()
		return

	var chosen_name := username_edit.text.strip_edges()
	if chosen_name.length() < 2:
		status_label.text = "Choose a name with at least 2 characters."
		username_edit.grab_focus()
		return

	connection_label.text = "● CONNECTING..."
	connection_label.add_theme_color_override(
		"font_color",
		Color(1.0, 0.72, 0.22)
	)
	status_label.text = "Connecting..."
	connect_button.text = "CONNECTING..."
	connect_button.disabled = true
	username_edit.editable = false

	# Server address is fixed inside OnlineSession. The player only chooses a
	# display name.
	session.connect_server(chosen_name)


func _on_connected(user: Dictionary) -> void:
	connection_label.text = "● CONNECTED"
	connection_label.add_theme_color_override(
		"font_color",
		Color(0.25, 1.0, 0.42)
	)

	identity_label.text = "Username: %s  |  Friend Code: %s" % [
		String(user.get("username", "Player")),
		String(user.get("friend_code", "-"))
	]

	status_label.text = "Connected"
	connect_button.text = "DISCONNECT"
	connect_button.disabled = false
	username_edit.editable = false

	if session != null:
		session.request_friend_list()


func _on_disconnected() -> void:
	connection_label.text = "● OFFLINE"
	connection_label.add_theme_color_override(
		"font_color",
		Color(1.0, 0.32, 0.32)
	)
	status_label.text = "Disconnected from server"
	identity_label.text = "Username: -  |  Friend Code: -"
	connect_button.text = "CONNECT"
	connect_button.disabled = false
	username_edit.editable = true


func _on_status(message: String) -> void:
	status_label.text = message
	var lower_message := message.to_lower()
	if lower_message.begins_with("connecting"):
		connection_label.text = "● CONNECTING..."
		connection_label.add_theme_color_override(
			"font_color",
			Color(1.0, 0.72, 0.22)
		)
	elif (
		"failed" in lower_message
		or "not connected" in lower_message
		or "disconnected" in lower_message
	):
		connection_label.text = "● OFFLINE"
		connection_label.add_theme_color_override(
			"font_color",
			Color(1.0, 0.32, 0.32)
		)
		connect_button.text = "CONNECT"
		connect_button.disabled = false
		username_edit.editable = true


func _on_add_friend() -> void:
	if session == null or friend_code_edit.text.strip_edges().is_empty():
		return
	session.add_friend(friend_code_edit.text)
	friend_code_edit.clear()


func _on_friend_list(payload: Dictionary) -> void:
	friends_payload = payload.duplicate(true)
	friend_list.clear()
	for friend in payload.get("friends", []):
		var state_text := (
			"ONLINE"
			if bool(friend.get("online", false))
			else "offline"
		)
		friend_list.add_item(
			"%s  [%s]" % [
				String(friend.get("username", "Player")),
				state_text
			]
		)
		friend_list.set_item_metadata(
			friend_list.item_count - 1,
			int(friend.get("id", 0))
		)

	request_list.clear()
	for incoming in payload.get("incoming", []):
		request_list.add_item(
			"%s  (%s)" % [
				String(incoming.get("username", "Player")),
				String(incoming.get("friend_code", ""))
			]
		)
		request_list.set_item_metadata(
			request_list.item_count - 1,
			int(incoming.get("id", 0))
		)


func _accept_selected_request() -> void:
	if session == null:
		return
	var selected := request_list.get_selected_items()
	if selected.is_empty():
		return
	var uid := int(request_list.get_item_metadata(selected[0]))
	session.accept_friend(uid)


func _invite_selected(mode: String) -> void:
	if session == null:
		return
	var selected := friend_list.get_selected_items()
	if selected.is_empty():
		return
	var uid := int(friend_list.get_item_metadata(selected[0]))
	session.invite_friend(uid, mode)


func _join_queue(mode: String) -> void:
	if session == null:
		return
	if not session.is_connected_to_server():
		status_label.text = "Connect first"
		return
	session.join_matchmaking(mode)


func _on_cancel_matchmaking() -> void:
	if session != null:
		session.cancel_matchmaking()


func _on_refresh_friends() -> void:
	if session != null:
		session.request_friend_list()


func _on_invite(payload: Dictionary) -> void:
	pending_invite = payload.duplicate(true)
	var from_data: Dictionary = payload.get("from", {}) as Dictionary
	invite_label.text = "%s invited you to %s" % [
		String(from_data.get("username", "Friend")),
		String(payload.get("mode", "normal")).to_upper()
	]
	accept_invite_button.visible = true


func _accept_pending_invite() -> void:
	if session == null or pending_invite.is_empty():
		return
	session.accept_match_invite(
		String(pending_invite.get("invite_id", ""))
	)
	accept_invite_button.visible = false
	invite_label.text = "Waiting for match..."
