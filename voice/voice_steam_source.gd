class_name VoiceSteamSource
extends VoiceMicSource
## Microphone samples from Steam Voice (ISteamUser StartVoiceRecording / GetVoice /
## DecompressVoice through GodotSteam), in place of the audio driver's input buffer (Patrick,
## 0.9.24: "i got it on 400% but its still quiet", then "use this approach": GodotSteam's voice).
## Steam records the microphone chosen in Steam > Settings > Voice, with Steam's own input volume,
## automatic gain and noise suppression, so a quiet USB mic at a low Windows level still arrives at
## a normal speaking level. What Steam hands over is decompressed right here (16 kHz, 16-bit mono)
## and goes through the same capture path as the driver's samples: Mic volume, the open-mic gate,
## 40 ms frames, the Steam lobby connection to the host, proximity and the listeners' jitter buffers.
##
## Steam only delivers audio while it hears speech: the gaps are filled with silence on the clock,
## so the stream stays continuous (the open-mic gate closes, talk spurts end, mouths shut).

## Rate Steam decompresses to (Steam accepts 11025..48000; the capture works at 16 kHz).
const RATE: int = 16000
## Silence fills in once Steam is this far behind the clock (its packets come in bursts).
const LAG_SECONDS: float = 0.12
## More than this ahead of the clock (a burst after a stall): the clock catches up.
const AHEAD_SECONDS: float = 0.3
## `EVoiceResult` k_EVoiceResultOK.
const VOICE_OK: int = 0
## GetVoice calls per read at most (each returns what Steam has waiting).
const MAX_READS: int = 8

## Steam voice sources recording (the settings panel's mic test can overlap the voice channel):
## Steam stops recording when the last one lets go.
static var _steam_users: int = 0

## Decompressed samples Steam delivered since `start` (silence fill not counted).
var steam_samples: int = 0
## How often each `EVoiceResult` came back from getVoice (0 OK, 1 not initialised, 2 not
## recording, 3 no data, 4 buffer too small, 5 data corrupted, 6 restricted, 7 unsupported codec,
## 8 receiver outdated, 9 receiver did not answer), for the log.
var results: Dictionary[int, int] = {}
## Seconds after `start` the first summary goes to the log.
const REPORT_AFTER_US: int = 5000000
var _start_us: int = -1
var _reported: bool = false
## Microsecond clock for the silence fill (tests replace it).
var clock: Callable = Time.get_ticks_usec
## Steam calls that failed (logged once).
var failures: int = 0

## The GodotSteam singleton (`SteamSvc.steam`; tests set a fake before `start`).
var _steam: Object = null
var _pending: PackedVector2Array = PackedVector2Array()
var _owed: float = 0.0
var _produced: float = 0.0
var _t_us: int = -1
var _logged_failure: bool = false


func _init() -> void:
	continuous = false


## True when Steam is running and Settings > Audio > Steam voice is on.
static func wanted() -> bool:
	return SteamSvc.is_available() and SteamSvc.steam != null and bool(Settings.get_value("voice", "steam_voice"))


func start() -> Error:
	error = ""
	if _started:
		return OK
	if _steam == null:
		_steam = SteamSvc.steam if SteamSvc.is_available() else null
	if _steam == null:
		error = "Steam voice needs the Steam client"
		return ERR_UNAVAILABLE
	if _steam_users == 0:
		_steam.call("startVoiceRecording")
		Log.info(&"voice", "Steam voice: recording started (Steam's optimal rate %s Hz, decompressing at %d Hz)" % [str(_steam.call("getVoiceOptimalSampleRate")) if _steam.has_method("getVoiceOptimalSampleRate") else "?", RATE])
	_steam_users += 1
	_started = true
	_pending.clear()
	_owed = 0.0
	_produced = 0.0
	_t_us = -1
	steam_samples = 0
	return OK


func stop() -> void:
	if not _started:
		return
	_started = false
	_report("stopped")
	_steam_users = maxi(_steam_users - 1, 0)
	if _steam_users == 0 and _steam != null:
		_steam.call("stopVoiceRecording")
	_pending.clear()


func available() -> int:
	_pull()
	return _pending.size()


func read(frames: int) -> PackedVector2Array:
	if frames > _pending.size():
		return PackedVector2Array()
	var out: PackedVector2Array = _pending.slice(0, frames)
	_pending = _pending.slice(frames)
	return out


func rate() -> float:
	return float(RATE)


func device() -> String:
	return "Steam voice"


func read_all() -> PackedVector2Array:
	_pull()
	var out: PackedVector2Array = _pending
	_pending = PackedVector2Array()
	return out


## Takes what Steam has (decompressed), then fills silence up to the clock.
func _pull() -> void:
	if not _started:
		return
	var now: int = int(clock.call())
	if _start_us < 0:
		_start_us = now
	elif not _reported and now - _start_us >= REPORT_AFTER_US:
		_report("after 5 s")
	if _t_us >= 0:
		_owed += (now - _t_us) / 1000000.0 * RATE
	_t_us = now
	for i: int in MAX_READS:
		var got: PackedFloat32Array = _read_steam()
		if got.is_empty():
			break
		append_mono(got)
		steam_samples += got.size()
	var lag: float = _owed - _produced
	if lag > RATE * LAG_SECONDS:
		append_mono(silence(int(lag - RATE * LAG_SECONDS)))
	elif -lag > RATE * AHEAD_SECONDS:
		_owed = _produced


func append_mono(samples: PackedFloat32Array) -> void:
	var at: int = _pending.size()
	_pending.resize(at + samples.size())
	for i: int in samples.size():
		_pending[at + i] = Vector2(samples[i], samples[i])
	_produced += samples.size()


static func silence(n: int) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(maxi(n, 0))
	return out


## One GetVoice + DecompressVoice: mono samples, empty when Steam has nothing (or failed).
func _read_steam() -> PackedFloat32Array:
	var got: Variant = _steam.call("getVoice")
	if not got is Dictionary:
		return PackedFloat32Array()
	var d: Dictionary = got
	var res: int = int(d.get("result", -1))
	results[res] = results.get(res, 0) + 1
	if res != VOICE_OK:
		return PackedFloat32Array()
	var buf: PackedByteArray = d.get("buffer", d.get("voice_data", PackedByteArray()))
	var written: int = int(d.get("written", d.get("size", buf.size())))
	if written <= 0 or buf.is_empty():
		return PackedFloat32Array()
	if written < buf.size():
		buf = buf.slice(0, written)
	var dec: Variant = _steam.call("decompressVoice", buf, RATE)
	var dres: int = int((dec as Dictionary).get("result", -1)) if dec is Dictionary else -1
	if dres != VOICE_OK:
		_fail("decompressVoice failed (result %d)" % dres)
		return PackedFloat32Array()
	var pcm: PackedByteArray = (dec as Dictionary).get("uncompressed", PackedByteArray())
	var size: int = int((dec as Dictionary).get("size", pcm.size()))
	return pcm16_to_float(pcm, mini(size, pcm.size()))


## Little-endian signed 16-bit PCM (`bytes` of it) → samples in [-1, 1].
static func pcm16_to_float(pcm: PackedByteArray, bytes: int) -> PackedFloat32Array:
	var n: int = bytes / 2
	var out := PackedFloat32Array()
	out.resize(n)
	for i: int in n:
		out[i] = pcm.decode_s16(i * 2) / 32768.0
	return out


## One log line: what getVoice answered and how much voice came of it.
func _report(when: String) -> void:
	_reported = true
	var parts: Array[String] = []
	for r: int in results:
		parts.append("%d×%d" % [r, results[r]])
	Log.info(&"voice", "Steam voice %s: getVoice results %s (result×count: 0 ok, 2 not recording, 3 no data), %.1f s of voice decompressed, %d decompress failures" % [when, ", ".join(PackedStringArray(parts)) if not parts.is_empty() else "none", steam_samples / float(RATE), failures])


func _fail(why: String) -> void:
	failures += 1
	if not _logged_failure:
		_logged_failure = true
		Log.warn(&"voice", "Steam voice: %s" % why)
