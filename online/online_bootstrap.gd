extends Node

const LOBBY_SCRIPT := preload("res://online/online_lobby.gd")

var lobby: RPSOnlineLobby
var hooked_button: Button
var starting_match := false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	print("ONLINE BOOTSTRAP READY")
	var session := get_node_or_null("/root/OnlineSession") as RPSOnlineSession
	if session != null:
		session.match_found.connect(_on_match_found)
		session.match_resumed.connect(_on_match_resumed)
	call_deferred("_try_hook_menu")

func _process(_delta: float) -> void:
	if hooked_button == null or not is_instance_valid(hooked_button):
		_try_hook_menu()

func _try_hook_menu() -> void:
	var button := get_tree().root.find_child(
		"TwoPlayerButton",
		true,
		false
	) as Button
	if button == null:
		return

	if hooked_button == button:
		return

	hooked_button = button

	# TwoPlayerButton already exists in MainMenuTransparent.tscn, but the
	# current scene stores it as visible=false. Turn that real menu button into
	# the Online entry instead of drawing over an invisible parent.
	button.visible = true
	button.disabled = false
	button.mouse_filter = Control.MOUSE_FILTER_STOP
	button.focus_mode = Control.FOCUS_NONE
	button.flat = false
	button.text = "آنلاین"
	button.tooltip_text = "Online Multiplayer"

	# Put Online on the second row, to the right of Tutorial.
	# Main menu design resolution is 2400x1080, so these offsets scale with the
	# existing canvas stretch exactly like the other menu hit areas.
	button.set_anchors_preset(Control.PRESET_TOP_LEFT)
	button.offset_left = 980.0
	button.offset_top = 565.0
	button.offset_right = 1245.0
	button.offset_bottom = 705.0

	button.add_theme_font_size_override("font_size", 46)
	button.add_theme_color_override(
		"font_color",
		Color(0.43, 0.20, 0.20, 1.0)
	)
	button.add_theme_color_override(
		"font_hover_color",
		Color(0.35, 0.12, 0.12, 1.0)
	)
	button.add_theme_color_override(
		"font_pressed_color",
		Color(0.30, 0.10, 0.10, 1.0)
	)

	var normal_style := StyleBoxFlat.new()
	normal_style.bg_color = Color(1.0, 0.84, 0.64, 1.0)
	normal_style.border_color = Color(0.30, 0.14, 0.10, 1.0)
	normal_style.set_border_width_all(3)
	normal_style.set_corner_radius_all(20)
	button.add_theme_stylebox_override("normal", normal_style)

	var hover_style := normal_style.duplicate() as StyleBoxFlat
	hover_style.bg_color = Color(1.0, 0.90, 0.72, 1.0)
	hover_style.set_border_width_all(4)
	button.add_theme_stylebox_override("hover", hover_style)

	var pressed_style := normal_style.duplicate() as StyleBoxFlat
	pressed_style.bg_color = Color(0.93, 0.74, 0.54, 1.0)
	button.add_theme_stylebox_override("pressed", pressed_style)

	var menu := _find_menu_from_button(button)
	if menu != null:
		# Keep the old local two-player callback disabled. Our Online callback
		# is connected to the same button.
		menu.set("disable_two_player_for_now", true)

	var callable := Callable(self, "_on_online_button_pressed")
	if not button.pressed.is_connected(callable):
		button.pressed.connect(callable)

	print("ONLINE BUTTON VISIBLE: ", button.get_path())


func _find_menu_from_button(button: Button) -> Node:
	var node: Node = button
	while node != null:
		if node is CanvasLayer and String(node.name) == "MainMenu":
			return node
		node = node.get_parent()
	return null

func _on_online_button_pressed() -> void:
	if starting_match:
		return
	if is_instance_valid(lobby):
		lobby.visible = true
		return
	lobby = LOBBY_SCRIPT.new() as RPSOnlineLobby
	lobby.name = "OnlineLobby"
	get_tree().root.add_child(lobby)
	lobby.close_requested.connect(_close_lobby)

func _close_lobby() -> void:
	if is_instance_valid(lobby):
		lobby.queue_free()
		lobby = null

func _on_match_found(payload: Dictionary) -> void:
	await _start_match(payload)

func _on_match_resumed(payload: Dictionary) -> void:
	# If the game scene is still alive after a short disconnect, MatchController
	# will keep its state. Otherwise start from the match setup again.
	var controller := get_tree().get_first_node_in_group(&"match_controller")
	if controller != null and bool(controller.get("online_mode")) and controller.get("state") != null:
		return
	await _start_match(payload)

func _start_match(payload: Dictionary) -> void:
	if starting_match:
		return
	starting_match = true
	_close_lobby()
	get_tree().paused = false

	var menu := get_tree().root.find_child("MainMenu", true, false)
	if menu != null:
		var cloud_controller = menu.get("cloud_controller")
		if is_instance_valid(cloud_controller):
			cloud_controller.queue_free()
		var intro_camera = menu.get("intro_camera")
		if is_instance_valid(intro_camera) and intro_camera.has_method(&"move_to_game_position"):
			await intro_camera.call(&"move_to_game_position")

	var controller := get_tree().get_first_node_in_group(&"match_controller")
	if controller == null:
		push_error("Online: MatchController3D not found.")
		starting_match = false
		return
	if not controller.has_method(&"begin_online_match"):
		push_error("Online: MatchController3D online integration is missing.")
		starting_match = false
		return

	var music_manager := get_node_or_null("/root/MusicManager")
	if music_manager != null and music_manager.has_method(&"play_game_music"):
		music_manager.call(&"play_game_music")

	if menu != null:
		menu.queue_free()
	await controller.call(&"begin_online_match", payload)
	starting_match = false
