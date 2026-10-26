class_name Emotes
extends RefCounted
## The emotes (§2.4.2): id, the emoji shown over the character, the wheel label, and the sound
## played with it (`emote_<id>` from audio/sfx/ when it exists, otherwise the fallback clip).
## Every emote, wheel or number key, is acted out by the character for `length(id)` (Patrick: "it
## actually animates your characters depending on the emote"; `AvatarVisuals.emote`), and the
## local player watches their own one in third person (`PlayerCamera.begin_emote_view`).

## [id, emoji, label, fallback sfx]. 6-7 sits at the top of the wheel (Patrick: "add a 67 emote").
const LIST: Array[Array] = [
	[&"six_seven", "🤲", "6-7", &"boing"],
	[&"wave", "👋", "WAVE", &"whistle"],
	[&"laugh", "😂", "LAUGH", &"boing"],
	[&"taunt", "😜", "TAUNT", &"whoosh"],
	[&"cry", "😭", "CRY", &"loss_sting"],
	[&"dance", "🕺", "DANCE", &"jump"],
	[&"gg", "🤝", "GG", &"coin"],
]
## Emotes on number keys 4-7 (`play_emote` intent → `player_emote` event), acted out by the bean
## for `length(id)`. Order = keys emote_1..emote_4: 6-7 on the 6 key.
const ANIMATED: Array[StringName] = [&"thumbs_up", &"thumbs_down", &"six_seven", &"default_dance"]
## How long a character acts an emote out unless `LENGTHS` says otherwise.
const SECONDS: float = 2.5
## Emotes that run longer or shorter than `SECONDS` (their choreography: `EmotePoses`). The server
## keeps an emote this long for late joiners.
const LENGTHS: Dictionary[StringName, float] = {
	&"six_seven": 3.0, &"wave": 2.6, &"laugh": 2.8, &"taunt": 2.8, &"cry": 3.0, &"dance": 3.4,
	&"gg": 3.0, &"thumbs_up": 2.2, &"thumbs_down": 2.4, &"default_dance": 3.4,
}
## The longest emote (`length` never exceeds it).
const MAX_SECONDS: float = 3.4


## How long emote `id` plays.
static func length(id: StringName) -> float:
	return LENGTHS.get(id, SECONDS)


## True for the animated (key) emotes.
static func is_animated(id: StringName) -> bool:
	return ANIMATED.has(id)


## True for every emote a character can act out: the wheel's and the number keys'.
static func has_animation(id: StringName) -> bool:
	return has(id) or is_animated(id)


static func has(id: StringName) -> bool:
	return index_of(id) >= 0


static func index_of(id: StringName) -> int:
	for i: int in LIST.size():
		if LIST[i][0] == id:
			return i
	return -1


## Speech-bubble text over the character: the emoji and the word ("👋 WAVE").
static func bubble_text(id: StringName) -> String:
	var i: int = index_of(id)
	return "%s %s" % [LIST[i][1], LIST[i][2]] if i >= 0 else "…"


## The sound to play: a dedicated `emote_<id>` clip wins over the fallback (&"" = none).
static func sound(id: StringName) -> StringName:
	var own: StringName = StringName("emote_%s" % id)
	for f: String in ["%s.wav", "%s.ogg", "%s-v1.ogg"]:
		if ResourceLoader.exists("res://audio/sfx/" + f % own):
			return own
	var i: int = index_of(id)
	return LIST[i][3] if i >= 0 else &""
