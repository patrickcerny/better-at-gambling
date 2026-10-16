class_name Emotes
extends RefCounted
## The emotes (§2.4.2): id, the emoji shown over the character, the wheel label, and the sound
## played with it (`emote_<id>` from audio/sfx/ when it exists, otherwise the fallback clip).
## Every emote, wheel or number key, is acted out by the character for `SECONDS` (Patrick: "it
## actually animates your characters depending on the emote"; `AvatarVisuals.emote`), and the
## local player watches their own one in third person (`PlayerCamera.begin_emote_view`).

## [id, emoji, label, fallback sfx]
const LIST: Array[Array] = [
	[&"wave", "👋", "WAVE", &"whistle"],
	[&"laugh", "😂", "LAUGH", &"boing"],
	[&"taunt", "😜", "TAUNT", &"whoosh"],
	[&"cry", "😭", "CRY", &"loss_sting"],
	[&"dance", "🕺", "DANCE", &"jump"],
	[&"gg", "🤝", "GG", &"coin"],
]
## Animated emotes on number keys 4-7 (`play_emote` intent → `player_emote` event): the bean (or
## skin) acts them out for `AvatarVisuals.EMOTE_SECONDS`. Order = keys emote_1..emote_4.
const ANIMATED: Array[StringName] = [&"six_seven", &"thumbs_up", &"thumbs_down", &"default_dance"]
## How long a character acts an emote out (the server keeps it this long for late joiners).
const SECONDS: float = 2.5


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


## The sound to play: a dedicated `emote_<id>` clip wins over the fallback.
static func sound(id: StringName) -> StringName:
	var own: StringName = StringName("emote_%s" % id)
	for f: String in ["%s.wav", "%s.ogg", "%s-v1.ogg"]:
		if ResourceLoader.exists("res://audio/sfx/" + f % own):
			return own
	var i: int = index_of(id)
	return LIST[i][3] if i >= 0 else &""
