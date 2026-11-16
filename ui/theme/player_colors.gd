class_name PlayerColors
extends RefCounted
## The colour that marks a player everywhere outside their bean (Patrick 2026-11-16: "this color
## (and anything else color coded) should be your skin color"): pedestal inlays, scoreboard and
## lobby rings, end-screen strips, money-graph lines, the dots on the station UIs, minigame props.
##
## It is the bean colour the player picked (`Palette.bean_color`), also under an animated skin.
## Everything comes from the shared match state (`bean_color` in every player's wire dictionary),
## so every client shows the same colours.
##
## Bean colours never repeat (`Cosmetics.bean_color_for`), but some sit close together (Cream and
## Champagne, Orange and Gold). `of_player` keeps such players apart: the lowest player id keeps
## their colour, a later one that would be too close gets a lighter, darker or slightly turned
## shade of it.

## Below this distance (`distance`) two colours count as "the same" on a graph or a scoreboard.
const MIN_DISTANCE: float = 0.17

static var _cache_key: String = ""
static var _cache: Dictionary = {}


## A player's own colour from their wire dictionary (`PlayerState.to_wire`), not kept apart from
## anyone else's: the bean colour they picked, also while they wear an animated skin (Patrick
## 2026-11-16: with the dev skin the pedestals went near-black, "das ist garnicht das was ich
## ausgewählt habe").
static func own(p: Dictionary) -> Color:
	return Palette.bean_color(p)


## Player `pid`'s colour among `players` (pid -> wire dictionary), shifted when an earlier player's
## colour is too close. `fallback` (a `Palette.player_color` index) when `pid` is not in `players`.
static func of_player(players: Dictionary, pid: int, fallback: int = -1) -> Color:
	var all: Dictionary = of_all(players)
	if all.has(pid):
		return all[pid]
	return Palette.player_color(fallback if fallback >= 0 else maxi(pid - 1, 0))


## Every player's colour (pid -> Color), told apart from each other. Cached until a player joins,
## leaves or changes colour.
static func of_all(players: Dictionary) -> Dictionary:
	var ids: Array = players.keys()
	ids.sort()
	var key_parts: PackedStringArray = []
	for pid: Variant in ids:
		var p: Dictionary = players[pid] if players[pid] is Dictionary else {}
		key_parts.append("%s:%d" % [str(pid), int(p.get("bean_color", p.get("color", 0)))])
	var key: String = ",".join(key_parts)
	if key == _cache_key:
		return _cache
	var taken: Array[Color] = []
	var out: Dictionary = {}
	for pid: Variant in ids:
		var p: Dictionary = players[pid] if players[pid] is Dictionary else {}
		var c: Color = distinct(own(p), taken)
		taken.append(c)
		out[pid] = c
	_cache_key = key
	_cache = out
	return out


## `c`, or the nearest shade of it that is at least `MIN_DISTANCE` from every colour in `taken`
## (the best one found when none is).
static func distinct(c: Color, taken: Array[Color]) -> Color:
	if _min_distance(c, taken) >= MIN_DISTANCE:
		return c
	var best: Color = c
	var best_d: float = _min_distance(c, taken)
	for step: int in range(1, 4):
		var t: float = 0.22 * step
		var hue: float = 0.06 * step
		for cand: Color in [c.lightened(t), c.darkened(t), _turned(c, hue), _turned(c, -hue)]:
			var d: float = _min_distance(cand, taken)
			if d >= MIN_DISTANCE:
				return cand
			if d > best_d:
				best_d = d
				best = cand
	return best


## How different two colours look (0 = same, about 1 = black against white): the "redmean"
## weighted RGB distance, close enough to perception for telling players apart.
static func distance(a: Color, b: Color) -> float:
	var rm: float = (a.r + b.r) * 0.5
	var dr: float = a.r - b.r
	var dg: float = a.g - b.g
	var db: float = a.b - b.b
	return sqrt(((2.0 + rm) * dr * dr + 4.0 * dg * dg + (3.0 - rm) * db * db) / 9.0)


static func _min_distance(c: Color, taken: Array[Color]) -> float:
	var m: float = INF
	for t: Color in taken:
		m = minf(m, distance(c, t))
	return m


## `c` with its hue turned by `amount` (0..1 = full circle); greys get some saturation so it shows.
static func _turned(c: Color, amount: float) -> Color:
	return Color.from_hsv(fposmod(c.h + amount, 1.0), maxf(c.s, 0.35), clampf(c.v, 0.25, 0.95), c.a)
