extends CanvasLayer


@export var idle_video: VideoStream
@export var start_video: VideoStream


@onready var video_player: VideoStreamPlayer = \
	$MenuRoot/VideoPlayer

@onready var start_button: Button = \
	$MenuRoot/StartButton

@onready var mode_buttons: Control = \
	$MenuRoot/ModeButtons

@onready var single_player_button: Button = \
	$MenuRoot/ModeButtons/SinglePlayerButton

@onready var two_player_button: Button = \
	$MenuRoot/ModeButtons/TwoPlayerButton


var transition_is_playing: bool = false


func _ready() -> void:
	start_button.show()
	mode_buttons.hide()

	start_button.pressed.connect(
		_on_start_button_pressed
	)

	single_player_button.pressed.connect(
		_on_single_player_button_pressed
	)

	two_player_button.pressed.connect(
		_on_two_player_button_pressed
	)

	_play_idle_video()


func _play_idle_video() -> void:
	video_player.paused = false
	video_player.loop = true
	video_player.stream = idle_video
	video_player.play()


func _on_start_button_pressed() -> void:
	if transition_is_playing:
		return

	transition_is_playing = true

	start_button.hide()
	mode_buttons.hide()

	video_player.paused = false
	video_player.loop = false
	video_player.stream = start_video
	video_player.play()

	await video_player.finished

	transition_is_playing = false

	# حالا دکمه‌های منوی دوم ظاهر می‌شوند.
	mode_buttons.show()


func _on_single_player_button_pressed() -> void:
	if transition_is_playing:
		return

	mode_buttons.hide()

	# منو حذف می‌شود و بازی فعلی قابل کنترل می‌شود.
	queue_free()


func _on_two_player_button_pressed() -> void:
	if transition_is_playing:
		return

	print("Two-player mode is not available yet.")
