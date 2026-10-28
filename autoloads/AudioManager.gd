## AudioManager.gd
## Autoloaded singleton that centralises all audio playback for the game.
## Having a single AudioManager node means:
##   • Scene transitions don't interrupt BGM (the node persists across scenes).
##   • Volume/bus settings are applied in one place.
##   • Any script can trigger sounds without needing a reference to a scene node.
##
## Loaded by Godot via project.godot [autoload] as "AudioManager".
## Usage examples:
##   AudioManager.play_ding()
##   AudioManager.play_sfx("res://audio/buy_property.wav")
##   AudioManager.play_bgm("res://audio/music/lobby_theme.ogg")

extends Node

# ---------------------------------------------------------------------------
# AUDIO PLAYER NODES
# These are created at runtime in _ready() so the autoload script file has no
# external scene dependency — it is entirely self-contained.
# ---------------------------------------------------------------------------

## bgm_player is dedicated to looping background music tracks.
## Using a separate AudioStreamPlayer (rather than sharing with SFX) means
## we can crossfade, loop, and stop music without affecting sound effects.
var bgm_player: AudioStreamPlayer

## sfx_player handles one-shot sound effects (dice roll, buy property, etc.).
## For overlapping SFX (multiple coins collected simultaneously) consider
## upgrading this to a pool of AudioStreamPlayers in a future iteration.
var sfx_player: AudioStreamPlayer

# ---------------------------------------------------------------------------
# LIFECYCLE
# ---------------------------------------------------------------------------

func _ready() -> void:
	# Instantiate both players here rather than in the scene tree so the
	# autoload script remains a plain .gd file (no companion .tscn needed).

	bgm_player = AudioStreamPlayer.new()
	# Assign BGM to the "Music" audio bus (defined in the Godot Audio panel).
	# This allows the user's "Music Volume" slider to control it independently
	# of SFX. Falls back silently to "Master" if the bus doesn't exist yet.
	bgm_player.bus = "Music"
	add_child(bgm_player)

	sfx_player = AudioStreamPlayer.new()
	# Assign SFX to the "SFX" audio bus for independent volume control.
	sfx_player.bus = "SFX"
	add_child(sfx_player)


# ---------------------------------------------------------------------------
# PUBLIC API
# ---------------------------------------------------------------------------

## play_ding
## Plays the turn-notification bell — the short "ding" that signals the next
## player that it is their turn to roll. This is called by the board scene
## immediately after advance_turn() fires the player_state_changed signal.
##
## TODO: Replace the placeholder with the real asset when it is available.
##   Load path: res://audio/ding.wav
##   The file should be a short (~0.3 s) triangle-wave bell hit.
##
## @return void
func play_ding() -> void:
	# ----- PLACEHOLDER -------------------------------------------------------
	# When the audio asset is ready, replace this block with:
	#
	#   var stream = load("res://audio/ding.wav") as AudioStream
	#   sfx_player.stream = stream
	#   sfx_player.play()
	#
	# For now we generate a minimal beep using AudioStreamGenerator so the
	# game is not silent during development without any asset files.
	# -------------------------------------------------------------------------

	var generator := AudioStreamGenerator.new()
	# 0.3 seconds of generated audio at 44 100 Hz sample rate.
	generator.mix_rate = 44100.0
	generator.buffer_length = 0.3

	sfx_player.stream = generator
	sfx_player.play()

	# Push a simple 880 Hz sine wave into the playback buffer.
	# This is a temporary stand-in only; real game audio should use .wav/.ogg.
	var playback := sfx_player.get_stream_playback() as AudioStreamGeneratorPlayback
	if playback:
		var frames: int = int(generator.mix_rate * generator.buffer_length)
		for i in range(frames):
			var t: float = float(i) / generator.mix_rate
			# 880 Hz (A5) sine wave with a simple linear decay envelope.
			var envelope: float = 1.0 - (float(i) / float(frames))
			var sample: float = sin(TAU * 880.0 * t) * envelope
			playback.push_frame(Vector2(sample, sample))  # stereo (L, R)


## play_sfx
## Loads an audio resource by path and plays it once through sfx_player.
## Suitable for all short, non-looping game events (dice roll, buy property,
## pay rent, go to jail, etc.).
##
## @param stream_path  A valid Godot resource path, e.g. "res://audio/dice.wav".
##                     The file must exist in the project or a push_error is logged.
## @return void
func play_sfx(stream_path: String) -> void:
	# Validate the path before attempting to load to give a clear error message.
	if stream_path.is_empty():
		push_warning("AudioManager.play_sfx: empty stream_path provided.")
		return

	# load() is synchronous. For large files consider ResourceLoader.load_threaded_*
	# but for short SFX (<1 MB) synchronous loading is acceptable.
	var stream = load(stream_path)
	if stream == null:
		push_error("AudioManager.play_sfx: could not load '%s'. Check the path." % stream_path)
		return

	sfx_player.stream = stream as AudioStream
	# play() restarts from the beginning; overlapping calls will cut off the
	# previous SFX. Use an AudioStreamPlayer pool if overlapping is required.
	sfx_player.play()


## play_bgm
## Loads an audio resource and starts it playing on bgm_player in a loop.
## Suitable for background music tracks during lobby, board gameplay, and
## victory screens. Stops any currently playing BGM before starting the new one.
##
## NOTE: For seamless looping, use .ogg files with loop-point metadata set in
## the Godot import settings (Import → Loop → Enabled).
##
## Audio asset placeholders (add files to res://audio/music/ when ready):
##   - Lobby theme:    res://audio/music/lobby_theme.ogg
##   - Board gameplay: res://audio/music/board_game.ogg
##   - Victory fanfare: res://audio/music/victory.ogg
##
## @param stream_path  A valid Godot resource path to an audio file.
## @return void
func play_bgm(stream_path: String) -> void:
	if stream_path.is_empty():
		push_warning("AudioManager.play_bgm: empty stream_path provided.")
		return

	# Stop any existing track first so we don't layer two songs.
	if bgm_player.playing:
		bgm_player.stop()

	var stream = load(stream_path)
	if stream == null:
		push_error("AudioManager.play_bgm: could not load '%s'." % stream_path)
		return

	bgm_player.stream = stream as AudioStream

	# Ensure looping is enabled at runtime regardless of import settings.
	# AudioStreamOggVorbis and AudioStreamMP3 expose a `loop` property.
	if bgm_player.stream.has_method("set_loop"):
		bgm_player.stream.set_loop(true)

	bgm_player.play()


## stop_bgm
## Immediately halts background music playback.
## Call this when transitioning to a scene that has its own music or when
## the game ends and silence is preferred over continued looping.
##
## @return void
func stop_bgm() -> void:
	if bgm_player.playing:
		bgm_player.stop()
