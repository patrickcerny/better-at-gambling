class_name VoiceJitterBuffer
extends RefCounted
## Per-speaker jitter buffer (§2.22: 100–150 ms). Frames arrive out of order, late, twice or not
## at all (unreliable channel); playback pulls one frame every 40 ms with `pop()`.
##
## - A talk spurt starts playing once `target_depth` frames are queued (or its last frame is in).
## - Frames are handed out strictly in sequence order; a missing frame whose successors have
##   already arrived counts as lost and is concealed (the previous frame, quieter, then silence).
## - A frame for a slot that already played is late and dropped; duplicates are dropped.
## - Running dry ends the spurt: the buffer refills to `target_depth` before playing again.
## - More than `max_depth` queued frames (a stall followed by a burst) drops the oldest so latency
##   doesn't grow without bound.

enum State { BUFFERING, PLAYING }

## Frames queued before a spurt starts: 3 × 40 ms = 120 ms.
var target_depth: int = 3
var max_depth: int = 12
var state: State = State.BUFFERING

var played: int = 0
var lost: int = 0
var late: int = 0
var duplicates: int = 0
var overflowed: int = 0

## seq → frame (decoded samples).
var _frames: Dictionary[int, PackedFloat32Array] = {}
var _end_seqs: Dictionary[int, bool] = {}
var _next: int = -1
var _last_frame: PackedFloat32Array = PackedFloat32Array()
var _concealed_in_row: int = 0


func _init(p_target_depth: int = 3, p_max_depth: int = 12) -> void:
	target_depth = maxi(p_target_depth, 1)
	max_depth = maxi(p_max_depth, target_depth + 1)


## Queues one frame. `end` marks the last frame of a talk spurt.
func push(seq: int, frame: PackedFloat32Array, end: bool = false) -> void:
	seq &= 0xFFFF
	if _frames.has(seq):
		duplicates += 1
		return
	if state == State.PLAYING and VoicePacket.seq_diff(seq, _next) < 0:
		late += 1
		return
	_frames[seq] = frame
	if end:
		_end_seqs[seq] = true
	while _frames.size() > max_depth:
		var oldest: int = _oldest()
		_frames.erase(oldest)
		_end_seqs.erase(oldest)
		overflowed += 1
		if state == State.PLAYING and VoicePacket.seq_diff(oldest, _next) >= 0:
			_next = (oldest + 1) & 0xFFFF


## Frames waiting to play.
func depth() -> int:
	return _frames.size()


## True while a spurt is playing or frames are waiting.
func is_active() -> bool:
	return state == State.PLAYING or not _frames.is_empty()


## The next frame to play: real audio, a concealment frame for a lost one, or an empty array when
## nothing is due (still buffering, or the spurt ran dry).
func pop() -> PackedFloat32Array:
	if state == State.BUFFERING:
		if _frames.size() < target_depth and _end_seqs.is_empty():
			return PackedFloat32Array()
		state = State.PLAYING
		_next = _oldest()
	if _frames.is_empty():
		_stop()
		return PackedFloat32Array()
	var seq: int = _next
	_next = (_next + 1) & 0xFFFF
	if _frames.has(seq):
		var f: PackedFloat32Array = _frames[seq]
		_frames.erase(seq)
		played += 1
		_last_frame = f
		_concealed_in_row = 0
		if _end_seqs.has(seq):
			_end_seqs.erase(seq)
			if _frames.is_empty():
				_stop()
		return f
	# A gap with later frames already here: the frame was lost (or is hopelessly late).
	lost += 1
	_concealed_in_row += 1
	return _conceal()


func _stop() -> void:
	state = State.BUFFERING
	_end_seqs.clear()
	_next = -1


func _conceal() -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(_last_frame.size() if not _last_frame.is_empty() else VoiceCodec.FRAME_SAMPLES)
	if _concealed_in_row == 1 and not _last_frame.is_empty():
		for i: int in out.size():
			out[i] = _last_frame[i] * 0.5
	return out


func _oldest() -> int:
	var best: int = -1
	for s: int in _frames:
		if best < 0 or VoicePacket.seq_diff(s, best) < 0:
			best = s
	return best
