class_name TransparentMainMenu
extends CanvasLayer


signal single_player_selected
signal two_player_selected
signal hardcore_selected


enum MenuPhase {
	IDLE,
	START_TRANSITION,
	MODE_SELECTION
}


@export_category("Game Intro Sequence")

@export var cloud_controller: CloudMenuController
@export var intro_camera: IntroCameraController
@export var match_controller: MatchController3D


@export_category("Transparent Video Pairs")

@export var idle_color_video: VideoStream
@export var idle_alpha_video: VideoStream

@export var start_color_video: VideoStream
@export var start_alpha_video: VideoStream


@export_category("Menu")

@export var pause_game_while_menu: bool = true
@export var disable_two_player_for_now: bool = true

@export_range(0.01, 0.25, 0.01)
var maximum_sync_drift: float = 0.06


@onready var menu_root: Control = $MenuRoot

@onready var color_player: VideoStreamPlayer = \
	$MenuRoot/ColorPlayer

@onready var alpha_player: VideoStreamPlayer = \
	$MenuRoot/AlphaPlayer

@onready var composite: ColorRect = \
	$MenuRoot/Composite

@onready var start_button: Button = \
	$MenuRoot/StartButton

@onready var mode_buttons: Control = \
	$MenuRoot/ModeButtons

@onready var single_player_button: Button = \
	$MenuRoot/ModeButtons/SinglePlayerButton

@onready var two_player_button: Button = \
	$MenuRoot/ModeButtons/TwoPlayerButton

@onready var hardcore_button: Button = \
	$MenuRoot/ModeButtons/HardcoreButton


var phase: int = MenuPhase.IDLE

var transition_is_running: bool = false
var game_transition_running: bool = false

var composite_material: ShaderMaterial


func _ready() -> void:
	# منو و ویدیوها حتی در حالت Pause اجرا می‌شوند.
	process_mode = Node.PROCESS_MODE_ALWAYS

	if pause_game_while_menu:
		get_tree().paused = true

	composite_material = composite.material as ShaderMaterial

	if composite_material == null:
		push_error(
			"Composite needs the transparent-video ShaderMaterial."
		)
		return

	start_button.show()
	mode_buttons.hide()

	two_player_button.disabled = \
		disable_two_player_for_now

	start_button.pressed.connect(
		_on_start_button_pressed
	)

	single_player_button.pressed.connect(
		_on_single_player_button_pressed
	)

	two_player_button.pressed.connect(
		_on_two_player_button_pressed
	)

	hardcore_button.pressed.connect(
		_on_hardcore_button_pressed
	)

	color_player.finished.connect(
		_on_color_video_finished
	)

	await _play_video_pair(
		idle_color_video,
		idle_alpha_video,
		MenuPhase.IDLE
	)


func _exit_tree() -> void:
	# در صورت حذف منو، بازی Pause باقی نماند.
	if (
		pause_game_while_menu
		and get_tree() != null
	):
		get_tree().paused = false


func _process(_delta: float) -> void:
	if not color_player.is_playing():
		return

	if not alpha_player.is_playing():
		return

	var drift: float = absf(
		color_player.stream_position
		- alpha_player.stream_position
	)

	if drift > maximum_sync_drift:
		alpha_player.stream_position = \
			color_player.stream_position


func _play_video_pair(
	color_stream: VideoStream,
	alpha_stream: VideoStream,
	new_phase: int
) -> void:
	if (
		color_stream == null
		or alpha_stream == null
	):
		push_error(
			"A color/alpha video pair is missing."
		)
		return

	phase = new_phase

	color_player.stop()
	alpha_player.stop()

	color_player.stream = color_stream
	alpha_player.stream = alpha_stream

	color_player.play()
	alpha_player.play()

	# یک فریم صبر می‌کنیم تا VideoTexture ساخته شود.
	await get_tree().process_frame

	composite_material.set_shader_parameter(
		"color_video",
		color_player.get_video_texture()
	)

	composite_material.set_shader_parameter(
		"alpha_video",
		alpha_player.get_video_texture()
	)


func _restart_idle_video() -> void:
	await _play_video_pair(
		idle_color_video,
		idle_alpha_video,
		MenuPhase.IDLE
	)


func _on_color_video_finished() -> void:
	match phase:
		MenuPhase.IDLE:
			# ویدیوهای Color و Alpha دوباره هم‌زمان
			# از اول اجرا می‌شوند.
			call_deferred(
				"_restart_idle_video"
			)

		MenuPhase.START_TRANSITION:
			transition_is_running = false
			phase = MenuPhase.MODE_SELECTION

			# آخرین فریم ویدیو باقی می‌ماند.
			mode_buttons.show()

		MenuPhase.MODE_SELECTION:
			pass


func _on_start_button_pressed() -> void:
	if transition_is_running:
		return

	if game_transition_running:
		return

	transition_is_running = true

	start_button.hide()
	mode_buttons.hide()

	await _play_video_pair(
		start_color_video,
		start_alpha_video,
		MenuPhase.START_TRANSITION
	)


func _on_single_player_button_pressed() -> void:
	if transition_is_running:
		return

	if game_transition_running:
		return

	# ربات معمولی فقط کارت‌های Revealشده را می‌بیند.
	ProjectSettings.set_setting(
		"gameplay/hardcore_bot",
		false
	)

	single_player_selected.emit()

	await _start_game_sequence()


func _on_hardcore_button_pressed() -> void:
	if transition_is_running:
		return

	if game_transition_running:
		return

	# ربات Hardcore کارت‌های Turn فعلی را هم می‌بیند.
	ProjectSettings.set_setting(
		"gameplay/hardcore_bot",
		true
	)

	hardcore_selected.emit()
	single_player_selected.emit()

	await _start_game_sequence()


func _start_game_sequence() -> void:
	if game_transition_running:
		return

	game_transition_running = true

	_disable_all_menu_buttons()

	# خود منو مخفی می‌شود تا خروج ابرها دیده شود.
	menu_root.hide()

	# ابرها و دوربین باید امکان اجرا داشته باشند.
	if pause_game_while_menu:
		get_tree().paused = false

	# -----------------------------------------
	# مرحله اول:
	# ابرها مستقیماً از ثانیه 8 تا 9 می‌روند.
	# -----------------------------------------
	if is_instance_valid(cloud_controller):
		cloud_controller.play_cloud_outro()

		await cloud_controller.clouds_outro_finished
	else:
		push_warning(
			"CloudController is not assigned."
		)

	# -----------------------------------------
	# مرحله دوم:
	# بعد از خروج کامل ابرها، دوربین جلو می‌رود.
	# -----------------------------------------
	if is_instance_valid(intro_camera):
		await intro_camera.move_to_game_position()
	else:
		push_warning(
			"IntroCameraController is not assigned."
		)

	# -----------------------------------------
	# مرحله سوم:
	# بعد از رسیدن دوربین، سه کارت Deck ظاهر می‌شوند.
	# -----------------------------------------
	var controller: MatchController3D = \
		_get_match_controller()

	if controller == null:
		push_error(
			"MatchController3D was not found."
		)
		game_transition_running = false
		return

	if not controller.has_method(
		&"begin_deck_selection"
	):
		push_error(
			"MatchController3D has no "
			+ "begin_deck_selection method."
		)
		game_transition_running = false
		return

	controller.begin_deck_selection()

	# دیگر به منو نیاز نداریم.
	queue_free()


func _get_match_controller() -> MatchController3D:
	# ابتدا از فیلد Inspector استفاده می‌شود.
	if is_instance_valid(match_controller):
		return match_controller

	# در صورت Assign نشدن، از Group پیدا می‌شود.
	var controller_node: Node = \
		get_tree().get_first_node_in_group(
			&"match_controller"
		)

	return controller_node as MatchController3D


func _disable_all_menu_buttons() -> void:
	var button_nodes: Array[Node] = \
		find_children(
			"*",
			"Button",
			true,
			false
		)

	for node: Node in button_nodes:
		var button := node as Button

		if button == null:
			continue

		button.disabled = true
		button.mouse_filter = \
			Control.MOUSE_FILTER_IGNORE


func _on_two_player_button_pressed() -> void:
	if transition_is_running:
		return

	if game_transition_running:
		return

	if disable_two_player_for_now:
		return

	two_player_selected.emit()

	if pause_game_while_menu:
		get_tree().paused = false

	queue_free()
