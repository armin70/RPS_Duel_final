extends Node


@export var background_music: AudioStream

@export_range(-80.0, 10.0, 0.5)
var music_volume_db: float = -10.0


@onready var music_player: AudioStreamPlayer = \
	$MusicPlayer

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	music_player.process_mode = Node.PROCESS_MODE_ALWAYS

	music_player.volume_db = music_volume_db

	# اگر از Inspector آهنگ داده شده، از آن استفاده کن.
	if background_music != null:
		music_player.stream = background_music

	# در غیر این صورت همان Stream داخل MusicPlayer را استفاده کن.
	if music_player.stream == null:
		push_error("Background music is not assigned.")
		return

	_enable_builtin_loop()

	if not music_player.finished.is_connected(
		_on_music_finished
	):
		music_player.finished.connect(
			_on_music_finished
		)

	if not music_player.playing:
		music_player.play(0.0)

func _enable_builtin_loop() -> void:
	var audio_stream: AudioStream = \
		music_player.stream

	if audio_stream is AudioStreamOggVorbis:
		var ogg_stream := \
			audio_stream as AudioStreamOggVorbis

		ogg_stream.loop = true
		ogg_stream.loop_offset = 0.0

	elif audio_stream is AudioStreamMP3:
		var mp3_stream := \
			audio_stream as AudioStreamMP3

		mp3_stream.loop = true
		mp3_stream.loop_offset = 0.0

	elif audio_stream is AudioStreamWAV:
		print(
			"WAV music detected. "
			+ "Using finished signal for looping."
		)


func _on_music_finished() -> void:
	# روش پشتیبان؛ برای هر فرمتی موزیک را دوباره پخش می‌کند.
	if music_player.stream == null:
		return

	music_player.play(0.0)

	print("BACKGROUND MUSIC LOOPED")


func play_music() -> void:
	if music_player.stream == null:
		return

	if not music_player.playing:
		music_player.play(0.0)


func stop_music() -> void:
	music_player.stop()


func pause_music() -> void:
	music_player.stream_paused = true


func resume_music() -> void:
	music_player.stream_paused = false


func set_music_volume(
	new_volume_db: float
) -> void:
	music_volume_db = new_volume_db
	music_player.volume_db = new_volume_db
