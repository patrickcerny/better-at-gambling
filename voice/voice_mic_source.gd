class_name VoiceMicSource
extends RefCounted
## Where `VoiceCapture` gets microphone samples from: the audio driver's input buffer, read
## directly through `AudioServer.get_input_frames()` at the device's own input rate.
##
## Voice used to play an `AudioStreamMicrophone` into a muted `Mic` bus and read it back through
## an `AudioEffectCapture` (0.9.0). That puts the microphone through the output mixer: it only
## runs while the stream "plays", is resampled to the output rate and back, and drifts against the
## device clock. Reading the driver buffer directly has none of that. Tests swap in a fake source.

## Name of the system default input device (always first in `AudioServer.get_input_device_list()`).
const DEFAULT_DEVICE: String = "Default"
## More than this much audio waiting means a stall or a device switch left stale audio in the
## driver's ring buffer: skip it and keep only the newest `KEEP_SECONDS`.
const STALE_SECONDS: float = 0.5
const KEEP_SECONDS: float = 0.1

## Live `VoiceMicSource`s holding the input device open (the settings panel's mic test can
## overlap the voice channel for a frame): the device stops when the last one lets go.
static var _users: int = 0

## Why `start` failed ("" while fine), for the HUD, the settings panel and the log.
var error: String = ""
## Stale frames `read_all` threw away (they still count as delivered for the rate check).
var skipped: int = 0
var _started: bool = false


## Starts the input device. OK, or an error with `error` set (headless, input disabled, no device).
func start() -> Error:
	error = ""
	if DisplayServer.get_name() == "headless":
		error = "no audio device (headless)"
		return ERR_UNAVAILABLE
	if not bool(ProjectSettings.get_setting("audio/driver/enable_input", false)):
		error = "audio input is disabled in the project settings"
		return ERR_UNAVAILABLE
	if _started:
		return OK
	var err: Error = OK if _users > 0 else AudioServer.set_input_device_active(true)
	if err != OK:
		# Godot keeps its "input active" flag set even when starting the device failed, and
		# would answer OK to every later attempt without trying again: clear it.
		AudioServer.set_input_device_active(false)
		error = "could not open the microphone \"%s\" (error %d)" % [device(), err]
		return err
	_started = true
	_users += 1
	return OK


func stop() -> void:
	if not _started:
		return
	_started = false
	_users = maxi(_users - 1, 0)
	if _users == 0:
		AudioServer.set_input_device_active(false)


## Stereo frames waiting to be read.
func available() -> int:
	return AudioServer.get_input_frames_available()


## Reads exactly `frames` stereo frames (fewer than `available()` returns an empty array).
func read(frames: int) -> PackedVector2Array:
	return AudioServer.get_input_frames(frames)


## Sample rate of what `read` returns.
func rate() -> float:
	return AudioServer.get_input_mix_rate()


## The input device in use ("Default" for the system default).
func device() -> String:
	return AudioServer.input_device


## Everything `read` has waiting, minus stale audio (see `STALE_SECONDS`).
func read_all() -> PackedVector2Array:
	var n: int = available()
	if n <= 0:
		return PackedVector2Array()
	var r: float = maxf(rate(), 1.0)
	if n > int(r * STALE_SECONDS):
		var keep: int = int(r * KEEP_SECONDS)
		read(n - keep)
		skipped += n - keep
		n = keep
	return read(n)
