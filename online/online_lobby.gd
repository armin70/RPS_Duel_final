class_name RPSOnlineLobby
extends CanvasLayer

signal close_requested

var session: RPSOnlineSession
var connection_label: Label
var status_label: Label
var identity_label: Label
var connect_button: Button
var server_edit: LineEdit
var username_edit: LineEdit
var friend_code_edit: LineEdit
var friend_list: ItemList
var request_list: ItemList
var deck_option: OptionButton
var hero_option: OptionButton
var slot_option: OptionButton
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
	panel.custom_minimum_size = Vector2(920, 690)
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
	connection_label.add_theme_color_override("font_color", Color(1.0, 0.32, 0.32))
	root.add_child(connection_label)

	status_label = Label.new()
	status_label.text = "Server not connected"
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status_label.add_theme_font_size_override("font_size", 18)
	root.add_child(status_label)

	identity_label = Label.new()
	identity_label.text = "Username: -  |  Friend Code: -"
	identity_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	identity_label.add_theme_font_size_override("font_size", 18)
	root.add_child(identity_label)

	var connect_row := HBoxContainer.new()
	root.add_child(connect_row)
	server_edit = LineEdit.new()
	server_edit.placeholder_text = "ws://127.0.0.1:8000/ws"
	server_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	connect_row.add_child(server_edit)
	username_edit = LineEdit.new()
	username_edit.placeholder_text = "Username"
	username_edit.custom_minimum_size.x = 180
	connect_row.add_child(username_edit)
	connect_button = Button.new()
	connect_button.text = "CONNECT"
	connect_button.custom_minimum_size.x = 150
	connect_button.pressed.connect(_on_connect_pressed)
	connect_row.add_child(connect_button)

	var sep1 := HSeparator.new()
	root.add_child(sep1)

	var setup_title := Label.new()
	setup_title.text = "MATCH SETUP"
	root.add_child(setup_title)
	var setup_row := HBoxContainer.new()
	root.add_child(setup_row)
	deck_option = OptionButton.new()
	for text in ["Deck 1", "Deck 2", "Deck 3"]:
		deck_option.add_item(text)
	setup_row.add_child(deck_option)
	hero_option = OptionButton.new()
	for text in ["Rostam", "Tahmineh", "Afrasiab"]:
		hero_option.add_item(text)
	setup_row.add_child(hero_option)
	slot_option = OptionButton.new()
	for text in [
		"Front Left", "Front Middle 0", "Front Middle 1", "Front Right",
		"Back Left", "Back Middle 0", "Back Middle 1", "Back Right"
	]:
		slot_option.add_item(text)
	setup_row.add_child(slot_option)
	var normal_button := Button.new()
	normal_button.text = "FIND NORMAL"
	normal_button.pressed.connect(func(): _join_queue("normal"))
	setup_row.add_child(normal_button)
	var rush_button := Button.new()
	rush_button.text = "FIND RUSH"
	rush_button.pressed.connect(func(): _join_queue("rush"))
	setup_row.add_child(rush_button)
	var cancel_queue := Button.new()
	cancel_queue.text = "CANCEL SEARCH"
	cancel_queue.pressed.connect(_on_cancel_matchmaking)
	setup_row.add_child(cancel_queue)

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
	friend_list.custom_minimum_size = Vector2(0, 180)
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
	request_list.custom_minimum_size = Vector2(0, 180)
	request_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	requests_box.add_child(request_list)
	var accept_friend_button := Button.new()
	accept_friend_button.text = "ACCEPT SELECTED"
	accept_friend_button.pressed.connect(_accept_selected_request)
	requests_box.add_child(accept_friend_button)

	invite_label = Label.new()
	invite_label.text = ""
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
	server_edit.text = String(session.server_url)
	username_edit.text = String(session.username)
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

	connection_label.text = "● CONNECTING..."
	connection_label.add_theme_color_override(
		"font_color",
		Color(1.0, 0.72, 0.22)
	)
	status_label.text = "Connecting to server..."
	connect_button.text = "CONNECTING..."
	connect_button.disabled = true

	session.connect_server(
		server_edit.text,
		username_edit.text
	)


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

	status_label.text = "Connected to server"
	connect_button.text = "DISCONNECT"
	connect_button.disabled = false
	server_edit.editable = false
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
	server_edit.editable = true
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

func _on_add_friend() -> void:
	if session == null or friend_code_edit.text.strip_edges().is_empty():
		return
	session.add_friend(friend_code_edit.text)
	friend_code_edit.clear()

func _on_friend_list(payload: Dictionary) -> void:
	friends_payload = payload.duplicate(true)
	friend_list.clear()
	for friend in payload.get("friends", []):
		var state_text := "ONLINE" if bool(friend.get("online", false)) else "offline"
		friend_list.add_item("%s  [%s]" % [String(friend.get("username", "Player")), state_text])
		friend_list.set_item_metadata(friend_list.item_count - 1, int(friend.get("id", 0)))
	request_list.clear()
	for incoming in payload.get("incoming", []):
		request_list.add_item("%s  (%s)" % [String(incoming.get("username", "Player")), String(incoming.get("friend_code", ""))])
		request_list.set_item_metadata(request_list.item_count - 1, int(incoming.get("id", 0)))

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
	session.invite_friend(uid, mode, _current_setup(mode))

func _join_queue(mode: String) -> void:
	if session == null:
		return
	if not session.is_connected_to_server():
		status_label.text = "Connect first"
		return
	session.join_matchmaking(mode, _current_setup(mode))

func _on_cancel_matchmaking() -> void:
	if session != null:
		session.cancel_matchmaking()


func _on_refresh_friends() -> void:
	if session != null:
		session.request_friend_list()


func _current_setup(mode: String) -> Dictionary:
	if mode == "rush":
		return {"deck_index": 1, "hero_kind": "none", "hero_slot": "none"}
	var hero_names := ["rostam", "tahmineh", "afrasiab"]
	var slot_names := [
		"front_left", "front_middle_0", "front_middle_1", "front_right",
		"back_left", "back_middle_0", "back_middle_1", "back_right"
	]
	return {
		"deck_index": deck_option.selected + 1,
		"hero_kind": hero_names[hero_option.selected],
		"hero_slot": slot_names[slot_option.selected]
	}

func _on_invite(payload: Dictionary) -> void:
	pending_invite = payload.duplicate(true)
	var from_data: Dictionary = payload.get("from", {}) as Dictionary
	invite_label.text = "%s invited you to %s" % [String(from_data.get("username", "Friend")), String(payload.get("mode", "normal")).to_upper()]
	accept_invite_button.visible = true

func _accept_pending_invite() -> void:
	if session == null or pending_invite.is_empty():
		return
	var mode := String(pending_invite.get("mode", "normal"))
	session.accept_match_invite(String(pending_invite.get("invite_id", "")), _current_setup(mode))
	accept_invite_button.visible = false
	invite_label.text = "Waiting for match..."
