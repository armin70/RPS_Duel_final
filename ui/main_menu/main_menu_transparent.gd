class_name TransparentMainMenu
extends CanvasLayer


signal single_player_selected
signal two_player_selected
signal hardcore_selected
signal rush_mode_selected


enum MenuPhase {
	IDLE,
	START_TRANSITION,
	MODE_SELECTION
}

@export_category("Help Video")
@export var help_video: VideoStream
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

@onready var help_button: Button = \
	$MenuRoot/ModeButtons/HelpButton
@onready var start_button: Button = $MenuRoot/StartButton

@onready var help_video_player: VideoStreamPlayer = \
	$MenuRoot/ModeButtons/HelpVideoPlayer
@onready var menu_root: Control = $MenuRoot
@onready var color_player: VideoStreamPlayer = $MenuRoot/ColorPlayer
@onready var alpha_player: VideoStreamPlayer = $MenuRoot/AlphaPlayer

@onready var composite: ColorRect = \
	$MenuRoot/Composite

@onready var mode_buttons: Control = \
	$MenuRoot/ModeButtons

@onready var single_player_button: Button = \
	$MenuRoot/ModeButtons/SinglePlayerButton
@onready var rush_button: Button = \
	$MenuRoot/ModeButtons/RushModeButton
@onready var tutorial_button: Button = $MenuRoot/ModeButtons/HelpButton

@onready var two_player_button: Button = \
	$MenuRoot/ModeButtons/TwoPlayerButton

@onready var hardcore_button: Button = \
	$MenuRoot/ModeButtons/HardcoreButton

@onready var alpha_notice: Control = $AlphaNotice
@onready var understood_button: TextureButton = $AlphaNotice/UnderstoodButton
var phase: int = MenuPhase.IDLE
var tutorial_mode_selected: bool = false
var rush_selected: bool = false
var transition_is_running: bool = false
var game_transition_running: bool = false

var composite_material: ShaderMaterial


const TUTORIAL_PROGRESS_PATH: String = \
	"user://tutorial_progress.cfg"
const TUTORIAL_PROGRESS_SECTION: String = "tutorial"
const TUTORIAL_PROGRESS_KEY: String = "completed"


func _ready() -> void:
	# Resolve the manager from /root instead of trusting the global
	# Autoload symbol. If the Autoload entry is missing/broken, create
	# exactly one persistent fallback instance so the menu never crashes.
	var music_manager := _get_or_create_music_manager()
	if music_manager != null and music_manager.has_method(&"play_menu_music"):
		music_manager.call(&"play_menu_music")

	menu_root.hide()
	alpha_notice.show()

	understood_button.pressed.connect(
		_on_understood_pressed
	)
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

	rush_button.pressed.connect(
		_on_rush_button_pressed
	)

	two_player_button.pressed.connect(
		_on_two_player_button_pressed
	)
	tutorial_button.pressed.connect(
		_on_tutorial_button_pressed
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

func _on_understood_pressed() -> void:
	alpha_notice.hide()
	menu_root.show()

func _on_help_button_pressed() -> void:
	if help_video == null:
		push_error("Help Video is not assigned.")
		return

	# UI منو مخفی می‌شود.
	start_button.hide()
	mode_buttons.hide()
	help_button.hide()

	# ویدیو یک بار از اول اجرا می‌شود.
	help_video_player.stream = help_video
	help_video_player.loop = false
	help_video_player.show()
	help_video_player.play()


func _on_help_video_finished() -> void:
	help_video_player.stop()
	help_video_player.hide()

	# برگرد به صفحه اول منو.
	phase = MenuPhase.IDLE
	transition_is_running = false

	start_button.show()
	mode_buttons.hide()
	help_button.show()

	# ویدیوی Idle منو دوباره از اول اجرا شود.
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
	_sync_video_pair(color_player, alpha_player)


func _sync_video_pair(
	primary: VideoStreamPlayer,
	secondary: VideoStreamPlayer
) -> void:
	if not is_instance_valid(primary):
		return

	if not is_instance_valid(secondary):
		return

	if not primary.is_playing():
		return

	if not secondary.is_playing():
		return

	var drift: float = absf(
		primary.stream_position
		- secondary.stream_position
	)

	if drift > maximum_sync_drift:
		secondary.stream_position = \
			primary.stream_position


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
	print("startttttttttttttttttttttt")
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

	ProjectSettings.set_setting(
		"gameplay/hardcore_bot",
		false
	)
	rush_selected = false

	# فقط اولین بار که بازیکن وارد Single Player می‌شود،
	# Tutorial به صورت خودکار اجرا می‌شود.
	tutorial_mode_selected = not _tutorial_has_been_completed()

	var controller: MatchController3D = \
		_get_match_controller()

	if controller != null:
		controller.tutorial_enabled = tutorial_mode_selected
		controller.rush_mode_enabled = false

	single_player_selected.emit()

	await _start_game_sequence()


func _tutorial_has_been_completed() -> bool:
	var config := ConfigFile.new()
	var load_error: Error = config.load(
		TUTORIAL_PROGRESS_PATH
	)

	# فایل هنوز وجود ندارد = اولین اجرای Tutorial.
	if load_error != OK:
		return false

	return bool(
		config.get_value(
			TUTORIAL_PROGRESS_SECTION,
			TUTORIAL_PROGRESS_KEY,
			false
		)
	)


func _on_tutorial_button_pressed() -> void:
	if transition_is_running:
		return

	if game_transition_running:
		return

	tutorial_mode_selected = true
	rush_selected = false

	ProjectSettings.set_setting(
		"gameplay/hardcore_bot",
		false
	)

	var controller: MatchController3D = \
		_get_match_controller()

	if controller != null:
		controller.tutorial_enabled = true
		controller.rush_mode_enabled = false

	single_player_selected.emit()

	await _start_game_sequence()


func _on_hardcore_button_pressed() -> void:
	tutorial_mode_selected = false
	rush_selected = false

	var controller: MatchController3D = \
		_get_match_controller()

	if controller != null:
		controller.tutorial_enabled = false
		controller.rush_mode_enabled = false
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


func _on_rush_button_pressed() -> void:
	if transition_is_running or game_transition_running:
		return

	tutorial_mode_selected = false
	rush_selected = true

	ProjectSettings.set_setting(
		"gameplay/hardcore_bot",
		false
	)

	var controller: MatchController3D = _get_match_controller()

	if controller != null:
		controller.tutorial_enabled = false
		controller.rush_mode_enabled = true

	rush_mode_selected.emit()
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
	# ابرها از ثانیه 8 تا 9 می‌روند.
	# -----------------------------------------
	if is_instance_valid(cloud_controller):
		cloud_controller.play_cloud_outro()

		await cloud_controller.clouds_outro_finished
		cloud_controller.queue_free()
		
		cloud_controller = null

		print("MENU CLOUDS REMOVED")
	else:
		push_warning(
			"CloudController is not assigned."
		)

	# -----------------------------------------
	# مرحله دوم:
	# حالا دوربین جلو می‌رود.
	# -----------------------------------------
	if is_instance_valid(intro_camera):
		await intro_camera.move_to_game_position()
		# ابرها دیگر در بازی استفاده نمی‌شوند.
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

	# The camera has reached the table: from this point on we are in gameplay,
	# so switch from the menu track to the match track.
	var music_manager := _get_or_create_music_manager()
	if music_manager != null and music_manager.has_method(&"play_game_music"):
		music_manager.call(&"play_game_music")

	if tutorial_mode_selected:
		await controller.begin_tutorial_match()
	elif rush_selected:
		await controller.begin_rush_match()
	else:
		controller.begin_deck_selection()

	# دیگر به منو نیاز نداریم.
	queue_free()


func _get_or_create_music_manager() -> Node:
	var root := get_tree().root
	if root == null:
		return null

	var existing := root.get_node_or_null("MusicManager")
	if existing != null:
		return existing

	var manager_scene := load("res://audio/music_manager.tscn") as PackedScene
	if manager_scene == null:
		push_error("Could not load res://audio/music_manager.tscn")
		return null

	var manager := manager_scene.instantiate()
	if manager == null:
		push_error("Could not instantiate MusicManager scene.")
		return null

	manager.name = "MusicManager"
	root.add_child(manager)
	push_warning(
		"MusicManager Autoload was missing; created a runtime fallback. "
		+ "Re-add res://audio/music_manager.tscn as the MusicManager Autoload."
	)
	return manager


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
