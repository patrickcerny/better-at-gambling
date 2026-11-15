class_name VoiceVad
extends RefCounted
## Speech detection for voice chat, relative to the room (0.9.32, Patrick: "Mic volume at 400 %
## for normal loudness"). The old open-mic gate was a fixed -45 dBFS: a microphone that speaks at
## -40..-50 dBFS (a USB mic at a low Windows level) barely opened it, so it needed the Mic volume
## turned all the way up, and the automatic level, which only moved on frames over that gate,
## never lifted it either.
##
## Here the background is tracked instead: the noise floor falls quickly to quieter frames and
## creeps up slowly through louder ones (speech has pauses, a fan does not), and a frame is speech
## when it stands `MARGIN_DB` over that floor. So a quiet mic in a quiet room opens the gate just
## like a loud one, and a steady hum does not.

## Speech stands this far over the noise floor (40 ms frame RMS).
const MARGIN_DB: float = 10.0
## Nothing quieter than this is ever speech (digital silence, a disconnected mic).
const MIN_SPEECH_DB: float = -72.0
## Where the floor starts before anything was heard (a quiet room through a quiet mic).
const START_FLOOR_DB: float = -60.0
## Frames under this (digital silence, a dropout) teach the floor nothing.
const IGNORE_UNDER_DB: float = -85.0
## The floor never goes under this or over that (above it, it is the speaker, not the room).
const FLOOR_MIN_DB: float = -80.0
const FLOOR_MAX_DB: float = -38.0
## Share of the way the floor falls to a quieter frame (a few frames of quiet bring it down).
const FALL: float = 0.3
## Floor rise per frame through louder frames: quick while it settles, then 1 dB/s.
const RISE_SETTLING_DB: float = 0.2
const RISE_DB: float = 0.04
## Frames the settling rise lasts (1 s).
const SETTLING_FRAMES: int = 25

## The room's level in dBFS.
var floor_db: float = START_FLOOR_DB
## The last frame was speech.
var speech: bool = false
var _frames: int = 0


func reset() -> void:
	floor_db = START_FLOOR_DB
	speech = false
	_frames = 0


## Judges one frame by its RMS level (dBFS) and learns the floor from it.
func process(db: float) -> bool:
	speech = db >= MIN_SPEECH_DB and db >= floor_db + MARGIN_DB
	if db < IGNORE_UNDER_DB:
		return speech
	if db < floor_db:
		floor_db = maxf(floor_db + (db - floor_db) * FALL, FLOOR_MIN_DB)
	else:
		floor_db = minf(floor_db + (RISE_SETTLING_DB if _frames < SETTLING_FRAMES else RISE_DB), minf(db, FLOOR_MAX_DB))
	_frames += 1
	return speech
