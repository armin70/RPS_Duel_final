extends Node


enum MusicContext {
	NONE,
	MENU,
	GAME
}


@export_category("Music Tracks")
@export var menu_music: AudioStream
@export var game_music: AudioStream

@export_category("Music Settings")
@export_range(-80.0, 10.0, 0.5)
var music_volume_db: float = -10.0


@onready var music_player: AudioStreamPlayer = $MusicPlayer

var current_context: int = MusicContext.NONE


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	music_player.process_mode = Node.PROCESS_MODE_ALWAYS
	music_player.volume_db = music_volume_db

	if not music_player.finished.is_connected(_on_music_finished):
		music_player.finished.connect(_on_music_finished)

	# The app opens on the menu, so use the menu track by default.
	# TransparentMainMenu also calls play_menu_music(), which is safe because
	# _switch_music() ignores requests for the track that is already playing.
	play_menu_music()


func play_menu_music() -> void:
	_switch_music(menu_music, MusicContext.MENU, "Menu Music")


func play_game_music() -> void:
	_switch_music(game_music, MusicContext.GAME, "Game Music")


func _switch_music(
	stream: AudioStream,
	new_context: int,
	label: String
) -> void:
	if stream == null:
		push_warning(label + " is not assigned in MusicManager.")
		return

	# Do not restart a track just because the same scene asks for it again.
	if (
		current_context == new_context
		and music_player.stream == stream
		and music_player.playing
	):
		return

	var was_paused: bool = music_player.stream_paused

	music_player.stop()
	music_player.stream = stream
	_enable_builtin_loop(stream)
	music_player.volume_db = music_volume_db
	music_player.play(0.0)

	# Keep the global mute/pause choice when changing from menu to game music
	# or back again.
	music_player.stream_paused = was_paused
	current_context = new_context


func _enable_builtin_loop(audio_stream: AudioStream) -> void:
	if audio_stream is AudioStreamOggVorbis:
		var ogg_stream := audio_stream as AudioStreamOggVorbis
		ogg_stream.loop = true
		ogg_stream.loop_offset = 0.0

	elif audio_stream is AudioStreamMP3:
		var mp3_stream := audio_stream as AudioStreamMP3
		mp3_stream.loop = true
		mp3_stream.loop_offset = 0.0

	elif audio_stream is AudioStreamWAV:
		print(
			"WAV music detected. "
			+ "Using finished signal for looping."
		)


func _on_music_finished() -> void:
	# Fallback loop for formats that do not use the built-in loop flag.
	if music_player.stream == null:
		return

	music_player.play(0.0)


func play_music() -> void:
	if music_player.stream == null:
		return

	if not music_player.playing:
		music_player.play(0.0)


func stop_music() -> void:
	music_player.stop()




func is_music_paused() -> bool:
	# Public query for UI code. Keep the AudioStreamPlayer private to this manager.
	if music_player == null:
		return true
	return music_player.stream_paused


func pause_music() -> void:
	music_player.stream_paused = true


func resume_music() -> void:
	music_player.stream_paused = false


func set_music_volume(new_volume_db: float) -> void:
	music_volume_db = new_volume_db
	music_player.volume_db = new_volume_db
