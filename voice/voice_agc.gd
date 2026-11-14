class_name VoiceAgc
extends RefCounted
## Automatic mic level for voice chat (Patrick, 0.9.17: "the microphone is SUPER quiet, people
## hear me INSANELY quietly"). A headset or laptop mic at Windows' default level speaks at
## -30..-45 dBFS RMS, 20 dB or more under the game's music, and the old Mic volume slider only
## added 6 dB. This brings every speaker's voice to the same healthy level before it is encoded
## (8-bit mu-law also keeps more detail of a loud signal than of a whisper).
##
## Only speech moves the gain (frames at least `SPEECH_DB` loud, judged by the caller): room hiss
## between words never pumps it up. A slow-falling envelope follows the loud syllables; the gain
## lifts that envelope to `TARGET_DB`, rising at most `RISE_DB` per frame and falling at once when
## the voice gets louder. It only ever boosts (a loud mic stays as it is), up to `MAX_BOOST_DB`.
## A rising gain ramps across the frame (no clicks), a falling one applies at once (no blast on the
## first loud word), and `limit` rounds off what would clip.

## Loud syllables land here (dBFS RMS of a 40 ms frame).
const TARGET_DB: float = -12.0
## Most the gain lifts a quiet mic (×16).
const MAX_BOOST_DB: float = 24.0
## Gain rise per speech frame (25 dB/s: a quiet speaker is up to level within the first word).
const RISE_DB: float = 1.0
## Envelope fall per speech frame towards a quieter frame (about 1 s to settle down).
const ENVELOPE_RELEASE: float = 0.04
## Frames under this (before the gain) are not speech and leave the gain alone.
const SPEECH_DB: float = -50.0
## Samples above this are rounded off smoothly by `limit` instead of clipping at full scale.
const LIMIT_KNEE: float = 0.6

## Current boost in dB (0 = as the mic hears it).
var gain_db: float = 0.0
## Loud-syllable level in dBFS (-100 until the first speech).
var envelope_db: float = -100.0


## Forgets the speaker (a new microphone, or the mic restarted).
func reset() -> void:
	gain_db = 0.0
	envelope_db = -100.0


## `frame` lifted to the voice level. `speech`: whether this frame is talking (the caller's gate
## decision, made on the un-boosted frame); other frames keep the current gain.
func process(frame: PackedFloat32Array, speech: bool) -> PackedFloat32Array:
	var from_db: float = gain_db
	var db: float = VoiceCodec.rms_db(frame)
	if speech and db >= SPEECH_DB:
		if db > envelope_db:
			envelope_db = db
		else:
			envelope_db += (db - envelope_db) * ENVELOPE_RELEASE
		var want: float = clampf(TARGET_DB - envelope_db, 0.0, MAX_BOOST_DB)
		gain_db = want if want < gain_db else minf(gain_db + RISE_DB, want)
	if is_zero_approx(from_db) and is_zero_approx(gain_db):
		return frame
	# Rising ramps across the frame; falling takes hold at once (the loud frame is what asked).
	var g0: float = db_to_linear(minf(from_db, gain_db))
	var g1: float = db_to_linear(gain_db)
	var out := PackedFloat32Array()
	var n: int = frame.size()
	out.resize(n)
	for i: int in n:
		out[i] = frame[i] * lerpf(g0, g1, float(i + 1) / n)
	return out


## Soft limiter: samples within ±`LIMIT_KNEE` pass untouched, louder ones bend towards full scale
## and never reach it (a turned-up voice saturates gently instead of crackling).
static func limit(frame: PackedFloat32Array) -> PackedFloat32Array:
	var out: PackedFloat32Array = frame
	var copied: bool = false
	var room: float = 1.0 - LIMIT_KNEE
	for i: int in frame.size():
		var x: float = frame[i]
		var a: float = absf(x)
		if a <= LIMIT_KNEE:
			continue
		if not copied:
			out = frame.duplicate()
			copied = true
		out[i] = signf(x) * (LIMIT_KNEE + room * tanh((a - LIMIT_KNEE) / room))
	return out
