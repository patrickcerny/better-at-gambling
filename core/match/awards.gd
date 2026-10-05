class_name Awards
extends RefCounted
## Fun awards for the results screen (§2.11), computed from per-player match stats.

## [stat key, award id, title, description format (%s = value)]. Order = priority.
const AWARDS: Array[Array] = [
	["jackpot_won", &"jackpot", "Jackpot!", "Hit the jackpot for $%s"],
	["biggest_win", &"big_winner", "Big Winner", "Biggest single win: $%s"],
	["quiz_points", &"quiz_wiz", "Quiz Wiz", "%s quiz points"],
	["comeback", &"comeback_kid", "Comeback Kid", "Places climbed from the bottom: %s"],
	["knockouts_dealt", &"heavyweight", "Heavyweight", "Knockouts dealt: %s"],
	["biggest_bet", &"high_roller", "High Roller", "Biggest single bet: $%s"],
	["loss_streak", &"unluckiest", "Unluckiest", "Lost %s bets in a row"],
	["shaken_out", &"sticky_fingers", "Sticky Fingers", "Shook $%s out of people"],
	["times_shoved", &"pinball", "Human Pinball", "Shoved around %s times"],
	["biggest_loss", &"glass_cannon", "Glass Cannon", "Biggest single loss: $%s"],
	["knockouts_suffered", &"ragdoll", "Ragdoll", "Knocked out %s times"],
	["thrown_out", &"bouncers_favorite", "Bouncer's Favorite", "Thrown out %s times"],
]

## Smallest value that earns an award (a single bad bet is not "unlucky").
const MINIMUM: Dictionary = {"loss_streak": 3, "times_shoved": 2, "knockouts_suffered": 2, "thrown_out": 2}


## Up to `count` awards [{id, title, text, player, name, value}], spread over different players
## where possible. Ties go to the lower player id; a zero stat earns nothing.
static func pick(stats: Dictionary, names: Dictionary, count: int) -> Array[Dictionary]:
	var candidates: Array[Dictionary] = []
	for a: Array in AWARDS:
		var best: int = -1
		var best_value: int = 0
		var ids: Array = stats.keys()
		ids.sort()
		for id: Variant in ids:
			var v: int = value_of(stats[id], a[0])
			if v > best_value and v >= int(MINIMUM.get(a[0], 1)):
				best_value = v
				best = int(id)
		if best >= 0:
			candidates.append({"id": a[1], "title": a[2], "text": str(a[3]) % _thousands(best_value), "player": best, "name": str(names.get(best, "Player %d" % best)), "value": best_value})
	var out: Array[Dictionary] = []
	var awarded: Dictionary = {}
	for c: Dictionary in candidates:
		if out.size() < count and not awarded.has(c["player"]):
			out.append(c)
			awarded[c["player"]] = true
	for c: Dictionary in candidates:
		if out.size() < count and not c in out:
			out.append(c)
	return out


## A stat's value (`comeback` = lowest rank reached minus final rank).
static func value_of(st: Dictionary, key: String) -> int:
	if key == "comeback":
		return maxi(int(st.get("lowest_rank", 1)) - int(st.get("final_rank", 1)), 0)
	return int(st.get(key, 0))


static func _thousands(n: int) -> String:
	var s: String = str(absi(n))
	var out: String = ""
	while s.length() > 3:
		out = "," + s.substr(s.length() - 3) + out
		s = s.substr(0, s.length() - 3)
	return ("-" if n < 0 else "") + s + out
