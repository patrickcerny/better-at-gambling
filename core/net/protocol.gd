class_name Protocol
extends RefCounted
## Network protocol constants (§4.1). Bump PROTOCOL_VERSION on any wire change.

const PROTOCOL_VERSION: int = 1
const DEFAULT_PORT: int = 24680
const MAX_PLAYERS: int = 8
const SERVER_TICK_HZ: int = 20
const MAX_INTENTS_PER_SECOND: int = 20

## ENet transfer channels.
const CHANNEL_EVENTS: int = 0
const CHANNEL_STATE: int = 1
const CHANNEL_PHYSICS: int = 2
const CHANNEL_VOICE: int = 3

## Room code alphabet: no ambiguous characters (0/O, 1/I/L).
const ROOM_CODE_ALPHABET: String = "ABCDEFGHJKMNPQRSTUVWXYZ23456789"
const ROOM_CODE_LENGTH: int = 5


## True if `code` is a well-formed room code.
static func is_valid_room_code(code: String) -> bool:
	if code.length() != ROOM_CODE_LENGTH:
		return false
	for ch: String in code:
		if not ROOM_CODE_ALPHABET.contains(ch):
			return false
	return true
