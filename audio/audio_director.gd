extends Node
## `Audio` autoload: one-shot SFX by name on the right bus, 3D SFX at a position, music by mood
## with smooth crossfades. Recorded clips (CC0 Kenney) where we have them, synthesized ones
## (`tools/audio/gen_sfx.py`) for the rest; music loops from `tools/audio/gen_music.py`. Missing
## clips log once and never block.

const SFX_DIR: String = "res://audio/sfx/"
const POOL_SIZE: int = 12
const CROSSFADE: float = 1.0
## Mood changes fade slower than a hard track switch: lounge music never cuts.
const MOOD_CROSSFADE: float = 2.5
## Music sits under the SFX; the Music bus (settings) scales this.
const MUSIC_DB: float = -6.0
## Moods (`set_mood`) and their loops in res://audio/music/.
const MOODS: Dictionary[StringName, StringName] = {
	&"menu": &"menu", &"casino": &"casino_base", &"quiz": &"quiz", &"minigame": &"quiz",
	&"last_call": &"last_call", &"results": &"results_winners",
}
const MAX_VARIANTS: int = 8

var _clips: Dictionary[StringName, Array] = {}
## Headless (dedicated servers, tests): nothing can be heard, so nothing is loaded or played.
var _silent: bool = false
var _missing: Dictionary[StringName, bool] = {}
var _pool: Array[AudioStreamPlayer] = []
var _music_a: AudioStreamPlayer
var _music_b: AudioStreamPlayer
var _music_current: AudioStreamPlayer
var _current_track: StringName = &""
var _mood: StringName = &""
var _fade: Tween = null


func _ready() -> void:
	_silent = DisplayServer.get_name() == "headless"
	for i: int in POOL_SIZE:
		var p := AudioStreamPlayer.new()
		p.bus = &"SFX"
		add_child(p)
		_pool.append(p)
	_music_a = AudioStreamPlayer.new()
	_music_b = AudioStreamPlayer.new()
	for m: AudioStreamPlayer in [_music_a, _music_b]:
		m.bus = &"Music"
		m.volume_db = -80.0
		add_child(m)
	_music_current = _music_a


func _exit_tree() -> void:
	# Release the streams before the engine's resource check at exit.
	_clips.clear()
	for p: AudioStreamPlayer in _pool + [_music_a, _music_b]:
		p.stop()
		p.stream = null


## Plays a 2D one-shot (UI and local-player feedback).
func play(name: StringName, bus: StringName = &"SFX", volume_db: float = 0.0, pitch: float = 1.0) -> void:
	if _silent:
		return
	var clip: AudioStream = _clip(name)
	if clip == null:
		return
	for p: AudioStreamPlayer in _pool:
		if not p.playing:
			p.stream = clip
			p.bus = bus
			p.volume_db = volume_db
			p.pitch_scale = pitch
			p.play()
			return


## Plays a positional one-shot under `parent` (freed when done).
func play_at(name: StringName, parent: Node3D, volume_db: float = 0.0, pitch: float = 1.0) -> void:
	if _silent:
		return
	var clip: AudioStream = _clip(name)
	if clip == null or parent == null or not parent.is_inside_tree():
		return
	var p := AudioStreamPlayer3D.new()
	p.stream = clip
	p.bus = &"SFX"
	p.volume_db = volume_db
	p.pitch_scale = pitch
	p.max_distance = 30.0
	parent.add_child(p)
	p.finished.connect(p.queue_free)
	p.play()


## The music for a moment of the game: &"menu", &"casino", &"quiz" (or &"minigame"),
## &"last_call", &"results"; &"" fades the music out. Calling it again with the same mood does
## nothing, so callers may set it every frame.
func set_mood(mood: StringName) -> void:
	if mood == _mood:
		return
	_mood = mood
	_crossfade(MOODS.get(mood, mood) if mood != &"" else &"", MOOD_CROSSFADE)


## Current mood (&"" when none was set).
func current_mood() -> StringName:
	return _mood


## Crossfades to a music track (`res://audio/music/<name>.ogg|wav`); &"" stops music. Old track
## names (`casino_loop`) map to their mood.
func play_music(name: StringName) -> void:
	if name == &"casino_loop":
		set_mood(&"casino")
		return
	_mood = name
	_crossfade(name, CROSSFADE)


func _crossfade(name: StringName, seconds: float) -> void:
	if _silent or name == _current_track:
		return
	_current_track = name
	var next: AudioStreamPlayer = _music_b if _music_current == _music_a else _music_a
	var stream: AudioStream = null
	for ext: String in ["ogg", "wav"]:
		var path: String = "res://audio/music/%s.%s" % [name, ext]
		if name != &"" and ResourceLoader.exists(path):
			stream = load(path)
			break
	if name != &"" and stream == null:
		Log.warn(&"audio", "missing music %s" % name)
	if stream is AudioStreamOggVorbis:
		(stream as AudioStreamOggVorbis).loop = true
	if _fade != null and _fade.is_valid():
		_fade.kill()
	# Equal-power fade in the linear domain (a dB ramp sounds like a dip in the middle).
	var prev: AudioStreamPlayer = _music_current
	var start: float = minf(db_to_linear(prev.volume_db - MUSIC_DB), 1.0) if prev.playing else 0.0
	_fade = create_tween().set_parallel(true)
	_fade.tween_method(func(v: float) -> void: prev.volume_db = linear_to_db(maxf(start * cos(v * PI * 0.5), 0.0001)) + MUSIC_DB, 0.0, 1.0, seconds)
	if stream != null:
		next.stream = stream
		next.volume_db = -80.0
		next.play()
		_fade.tween_method(func(v: float) -> void: next.volume_db = linear_to_db(maxf(sin(v * PI * 0.5), 0.0001)) + MUSIC_DB, 0.0, 1.0, seconds)
	_fade.chain().tween_callback(func() -> void:
		if prev != _music_current:
			prev.stop())
	_music_current = next


## Sets a bus volume in linear 0..1 units. Unknown buses are ignored with a warning.
func set_bus_volume(bus_name: StringName, linear: float) -> void:
	var idx: int = AudioServer.get_bus_index(bus_name)
	if idx < 0:
		Log.warn(&"audio", "unknown bus %s" % bus_name)
		return
	AudioServer.set_bus_volume_db(idx, linear_to_db(clampf(linear, 0.0001, 1.0)))


func _clip(name: StringName) -> AudioStream:
	if not _clips.has(name) and not _missing.has(name):
		_load(name)
	var list: Array = _clips.get(name, [])
	if list.is_empty():
		return null
	return list[randi() % list.size()]


## Recorded variants `<name>-v1.ogg`, `-v2.ogg`… (CC0 Kenney packs, see audio/sfx/KENNEY_LICENSE.txt)
## win over the generated `<name>.wav` placeholder; one is picked at random per play.
func _load(name: StringName) -> void:
	var list: Array = []
	for i: int in range(1, MAX_VARIANTS + 1):
		var vpath: String = "%s%s-v%d.ogg" % [SFX_DIR, name, i]
		if not ResourceLoader.exists(vpath):
			break
		list.append(load(vpath))
	if list.is_empty():
		for ext: String in ["ogg", "wav"]:
			var path: String = "%s%s.%s" % [SFX_DIR, name, ext]
			if ResourceLoader.exists(path):
				list.append(load(path))
				break
	if list.is_empty():
		_missing[name] = true
		Log.warn(&"audio", "missing sfx %s" % name)
		return
	_clips[name] = list
