extends Node
## Plays the game's sound effects and music.
##
## Every sound has a branded synthesised version (see SoundSynth) so the game
## always has its own consistent audio. If you add a file with the same base
## name to res://assets/audio/ (.ogg, .wav or .mp3) it replaces the synth one.
## Synth renders are cached in user:// so later launches start instantly.

const AUDIO_DIR := "res://assets/audio/"
const CACHE_DIR := "user://sound_cache/"
const EXTENSIONS: Array[String] = ["ogg", "wav", "mp3"]
const POOL_SIZE := 10

## Sound id used in code -> optional override file base name in res://assets/audio/.
const SOUNDS := {
	"pop": "block_pop",
	"wobble": "block_wobble",
	"rumble": "rock_rumble",
	"sizzle": "lava_sizzle",
	"roll": "boulder_roll",
	"creak": "plank_creak",
	"tear": "cloth_tear",
	"win": "win",
	"lose": "lose",
	"click": "button_click",
	"star": "star",
	"thud": "impact",
	"swoosh": "swoosh",
}
const MUSIC_FILE := "music"
const MUSIC_DB := -11.0

var _streams: Dictionary = {}  # id -> AudioStream
var _pool: Array[AudioStreamPlayer] = []
var _loops: Dictionary = {}  # id -> AudioStreamPlayer for continuous sounds
var _music: AudioStreamPlayer
var _music_wanted: bool = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	DirAccess.make_dir_recursive_absolute(CACHE_DIR)
	for i in POOL_SIZE:
		var p := AudioStreamPlayer.new()
		add_child(p)
		_pool.append(p)
	for id: String in SOUNDS.keys():
		var stream := _find_file(String(SOUNDS[id]))
		_streams[id] = stream if stream != null else _synth(id)
	_music = AudioStreamPlayer.new()
	_music.volume_db = MUSIC_DB
	add_child(_music)
	var music_file := _find_file(MUSIC_FILE)
	if music_file != null:
		_set_music_stream(music_file)
	elif ResourceLoader.exists(_cache_path("music")):
		_set_music_stream(load(_cache_path("music")) as AudioStream)
	else:
		# ~20 s of music takes a moment to render: do it off the main thread.
		WorkerThreadPool.add_task(_render_music_async)


func _find_file(base_name: String) -> AudioStream:
	for ext in EXTENSIONS:
		var path := "%s%s.%s" % [AUDIO_DIR, base_name, ext]
		if ResourceLoader.exists(path):
			return load(path) as AudioStream
	return null


func _cache_path(id: String) -> String:
	return "%sv%d_%s.res" % [CACHE_DIR, SoundSynth.VERSION, id]


## Synthesised sound, loaded from the user:// cache when available.
func _synth(id: String) -> AudioStream:
	var path := _cache_path(id)
	if ResourceLoader.exists(path):
		var cached := load(path) as AudioStream
		if cached != null:
			return cached
	var stream := SoundSynth.build(id)
	if stream != null:
		ResourceSaver.save(stream, path)
	return stream


func _render_music_async() -> void:
	var stream := SoundSynth.build("music")
	_on_music_rendered.call_deferred(stream)


func _on_music_rendered(stream: AudioStreamWAV) -> void:
	ResourceSaver.save(stream, _cache_path("music"))
	_set_music_stream(stream)


func _set_music_stream(stream: AudioStream) -> void:
	_music.stream = stream
	if stream is AudioStreamWAV:
		(stream as AudioStreamWAV).loop_mode = AudioStreamWAV.LOOP_FORWARD
	elif stream is AudioStreamOggVorbis:
		(stream as AudioStreamOggVorbis).loop = true
	elif stream is AudioStreamMP3:
		(stream as AudioStreamMP3).loop = true
	if _music_wanted:
		play_music()


func has_sound(id: String) -> bool:
	return _streams.get(id) != null


## Plays a one-shot sound with slight random pitch so repeats don't sound robotic.
func play(id: String, volume_db: float = 0.0, pitch: float = 1.0, jitter: float = 0.06) -> void:
	if not GameState.sfx_on:
		return
	var stream: AudioStream = _streams.get(id)
	if stream == null:
		return
	var player := _pool[0]
	for p in _pool:
		if not p.playing:
			player = p
			break
	player.stream = stream
	player.volume_db = volume_db
	player.pitch_scale = pitch * randf_range(1.0 - jitter, 1.0 + jitter)
	player.play()


## Starts/stops a continuous sound (rock rumble, lava sizzle, boulder roll).
## Call every few frames with a new volume while active.
func set_loop(id: String, active: bool, volume_db: float = 0.0) -> void:
	var stream: AudioStream = _streams.get(id)
	if stream == null:
		return
	var player: AudioStreamPlayer = _loops.get(id)
	if player == null:
		player = AudioStreamPlayer.new()
		player.stream = stream
		add_child(player)
		# Restart when finished so non-looping override files still loop.
		player.finished.connect(func() -> void:
			if bool(player.get_meta("active", false)):
				player.play())
		_loops[id] = player
	var on := active and GameState.sfx_on
	player.set_meta("active", on)
	# Smooth volume changes to avoid zipper noise.
	player.volume_db = lerpf(player.volume_db, volume_db, 0.5) if player.playing else volume_db
	if on and not player.playing:
		player.play()
	elif not on and player.playing:
		player.stop()


func stop_all_loops() -> void:
	for id: String in _loops.keys():
		set_loop(id, false)


func play_music() -> void:
	_music_wanted = true
	if _music.stream == null or not GameState.music_on:
		return
	if not _music.playing:
		_music.play()


func stop_music() -> void:
	_music_wanted = false
	_music.stop()


## Ducks the music briefly (e.g. under the win/lose jingle).
func duck_music(seconds: float) -> void:
	var tw := create_tween()
	tw.tween_property(_music, "volume_db", MUSIC_DB - 14.0, 0.15)
	tw.tween_interval(seconds)
	tw.tween_property(_music, "volume_db", MUSIC_DB, 0.8)


func set_music_enabled(on: bool) -> void:
	GameState.music_on = on
	GameState.save_progress()
	if on:
		play_music()
	else:
		_music.stop()


func set_sfx_enabled(on: bool) -> void:
	GameState.sfx_on = on
	GameState.save_progress()
	if not on:
		stop_all_loops()


## Stop everything on shutdown so the audio server releases its playbacks
## (otherwise Godot reports leaked AudioStreamPlayback instances at exit).
func _exit_tree() -> void:
	_music.stop()
	_music.stream = null
	for p in _pool:
		p.stop()
		p.stream = null
	for id: String in _loops.keys():
		var player: AudioStreamPlayer = _loops[id]
		player.stop()
		player.stream = null
