class_name Emotes
extends RefCounted
## The emotes (§2.4.2): id, the emoji shown over the character, the wheel label, and the sound
## played with it (`emote_<id>` from audio/sfx/ when it exists, otherwise the fallback clip).

## [id, emoji, label, fallback sfx]
const LIST: Array[Array] = [
	[&"wave", "👋", "WAVE", &"whistle"],
	[&"laugh", "😂", "LAUGH", &"boing"],
	[&"taunt", "😜", "TAUNT", &"whoosh"],
	[&"cry", "😭", "CRY", &"loss_sting"],
	[&"dance", "🕺", "DANCE", &"jump"],
	[&"gg", "🤝", "GG", &"coin"],
]


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
