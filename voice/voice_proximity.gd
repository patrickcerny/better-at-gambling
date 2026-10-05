class_name VoiceProximity
extends RefCounted
## Who hears whom (§2.22). Pure rules, used by the server relay:
## - within `HEARING_RADIUS` metres: heard, positioned in 3D (full volume within `FULL_VOLUME_RADIUS`,
##   fading to silence at the edge);
## - seated at the same table: heard at full volume regardless of distance;
## - quiz, rewards and results: everyone hears everyone (game-show stage, podium gloating).

enum Reach { NONE, NEAR, TABLE, GLOBAL }

const HEARING_RADIUS: float = 20.0
const FULL_VOLUME_RADIUS: float = 4.0
## Phases where voice is global.
const GLOBAL_PHASES: Array[Phase.Id] = [Phase.Id.MINIGAME, Phase.Id.REWARDS, Phase.Id.RESULTS]


static func is_global_phase(phase: Phase.Id) -> bool:
	return phase in GLOBAL_PHASES


## How a listener hears a speaker. Stations are &"" when not seated.
static func reach(phase: Phase.Id, speaker_pos: Vector3, listener_pos: Vector3, speaker_station: StringName = &"", listener_station: StringName = &"") -> Reach:
	if is_global_phase(phase):
		return Reach.GLOBAL
	if speaker_station != &"" and speaker_station == listener_station:
		return Reach.TABLE
	if speaker_pos.distance_to(listener_pos) <= HEARING_RADIUS:
		return Reach.NEAR
	return Reach.NONE


## Packet flags for a reach (see `VoicePacket`).
static func flags_for(r: Reach) -> int:
	match r:
		Reach.GLOBAL:
			return VoicePacket.FLAG_GLOBAL
		Reach.TABLE:
			return VoicePacket.FLAG_TABLE
	return 0
