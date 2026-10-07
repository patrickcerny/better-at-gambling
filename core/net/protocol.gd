class_name Protocol
extends RefCounted
## Network protocol constants (§4.1). Bump PROTOCOL_VERSION on any wire change.

const PROTOCOL_VERSION: int = 5
## Build string clients and servers must share exactly (the orchestrator checks it too).
const BUILD_ID: String = "0.7.4-rules"
const DEFAULT_PORT: int = 24680
const MAX_PLAYERS: int = 8
const SERVER_TICK_HZ: int = 20
const MAX_INTENTS_PER_SECOND: int = 20

## ENet transfer channels: events/intents and state are reliable+ordered; the 20 Hz movement
## and world streams and voice are unreliable (newest wins).
const CHANNEL_EVENTS: int = 0
const CHANNEL_STATE: int = 1
const CHANNEL_PHYSICS: int = 2
## Voice frames are raw `VoicePacket` bytes, not `Wire` messages: client → server → listeners in
## reach (`VoiceRelay`).
const CHANNEL_VOICE: int = 3

## Message types: every packet is `[type, payload]` (see `Wire`).
enum Msg {
	HELLO = 1,  ## C→S {protocol, build, join_token, name, uid, color, skin}
	WELCOME,  ## S→C {player, snapshot, private, server_time}
	REJECT,  ## S→C {code, message}
	EVENT,  ## S→C one game event (reliable, ordered)
	INTENT,  ## C→S one intent (reliable)
	INTENT_RESULT,  ## S→C {type, error} for intents refused before reaching game logic
	MOVE,  ## C→S {pos, yaw, airborne, seq} (unreliable): own avatar while standing
	WORLD,  ## S→C WorldCodec bytes (unreliable, 20 Hz)
	STATUS,  ## S→C {time_left, next_minigame_in, casino_time, jackpot, stations (changed only)}
	SNAPSHOT_REQ,  ## C→S {}
	SNAPSHOT,  ## S→C full MatchServer snapshot
	PRIVATE,  ## S→C this player's private station data
	PING,  ## C→S {t}
	PONG,  ## S→C {t, server_time}
	FORCE_POSITION,  ## S→C {pos, yaw}: movement sanity snap-back
	BYE,  ## C→S leaving on purpose
}

## Rejection codes (REJECT.code) with player-facing text.
const REJECT_TEXT: Dictionary = {
	&"version_mismatch": "The server is on a different version. Update the game and try again.",
	&"bad_token": "Could not verify your invitation. Try joining again.",
	&"room_full": "This party is full.",
	&"room_in_progress": "The match already started. Only players who were in it can rejoin.",
	&"server_error": "Server error. Returning to the menu.",
	&"timeout": "Could not reach the server.",
}

## Room code alphabet: no ambiguous characters (0/O, 1/I/L).
const ROOM_CODE_ALPHABET: String = "ABCDEFGHJKMNPQRSTUVWXYZ23456789"
const ROOM_CODE_LENGTH: int = 5


## True if packets on `channel` are sent reliably.
static func is_reliable_channel(channel: int) -> bool:
	return channel == CHANNEL_EVENTS or channel == CHANNEL_STATE


## True if `code` is a well-formed room code.
static func is_valid_room_code(code: String) -> bool:
	if code.length() != ROOM_CODE_LENGTH:
		return false
	for ch: String in code:
		if not ROOM_CODE_ALPHABET.contains(ch):
			return false
	return true
