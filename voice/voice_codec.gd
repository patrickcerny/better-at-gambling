class_name VoiceCodec
extends RefCounted
## Voice codec interface (§2.22) and the voice format every codec shares: 8 kHz mono, 40 ms
## frames. The rest of the voice code only sees `encode`/`decode`, so a Steam Voice or Opus codec
## can replace `MulawCodec` later without touching capture, relay or playback.

## Samples per second on the wire (telephone band: plenty for chatter, half the 16 kHz budget).
const SAMPLE_RATE: int = 8000
## One frame per packet.
const FRAME_MS: int = 40
## SAMPLE_RATE × FRAME_MS / 1000.
const FRAME_SAMPLES: int = 320
const FRAME_SECONDS: float = 0.04


## Encodes one frame of samples in [-1, 1].
func encode(_samples: PackedFloat32Array) -> PackedByteArray:
	return PackedByteArray()


## Decodes one encoded frame back to samples in [-1, 1].
func decode(_bytes: PackedByteArray) -> PackedFloat32Array:
	return PackedFloat32Array()


## Root mean square of a block of samples (0 for an empty block).
static func rms(samples: PackedFloat32Array) -> float:
	if samples.is_empty():
		return 0.0
	var sum: float = 0.0
	for x: float in samples:
		sum += x * x
	return sqrt(sum / samples.size())


## RMS in dBFS (−100 for silence).
static func rms_db(samples: PackedFloat32Array) -> float:
	var r: float = rms(samples)
	return linear_to_db(r) if r > 0.00001 else -100.0
