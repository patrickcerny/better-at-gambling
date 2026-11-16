class_name DailyWheel
extends RefCounted
## The Daily Spin (Patrick 2026-11-16: "Daily spin button auf der Startseite wo du Sachen gewinnen
## kannst, auch die gezahlte Währung und sehr unwahrscheinlich ein krasser animierter Skin"): one
## free spin of a prize wheel every `COOLDOWN_S`. Nothing is paid for a spin, so it is no loot box.
##
## With Steam the spin is decided by Steam, not by the game: SPIN triggers the item drop of
## `GENERATOR` (a Steam Inventory "playtimegenerator" that grants once per `COOLDOWN_MIN` per
## account and picks one prize by the weights below, tools/steam/itemdefs.json). The prize arrives
## in the Steam inventory as a token the game redeems: red Coin tokens and the mystery piece token
## are consumed and paid out into the profile, Gold Coin tokens are exchanged by Steam for Gold
## Coins (`gold_bundle`), and the Fortune skin is granted directly. A hacked client can't spin twice
## a day or win Gold it wasn't given, because Steam keeps both the timer and the Gold.
##
## Without Steam (or before the item definitions are on Steam) the game rolls locally, red Coins and
## mystery pieces only; the timer then runs on the profile and the clock (`next_spin_at`).

const KIND_COINS: StringName = &"coins"
const KIND_PIECE: StringName = &"piece"
const KIND_GOLD: StringName = &"gold"
const KIND_SKIN: StringName = &"skin"

## The Steam playtime generator that is the spin.
const GENERATOR: int = 3200
## Steam's limit: one drop per window of this many minutes; the local timer is the same.
const COOLDOWN_MIN: int = 20 * 60
const COOLDOWN_S: int = COOLDOWN_MIN * 60
## Gold prizes: the bundle granting N Gold Coins is its token's id + this.
const GOLD_BUNDLE_OFFSET: int = 100
## The wheel's only exclusive: the Fortune skin (`CosmeticDef.wheel_only`).
const SKIN_ID: StringName = &"skin_fortune"
## A mystery piece when every normal piece is owned already pays this many Coins instead.
const PIECE_FALLBACK_COINS: int = 750
## The weights add up to this (per mille).
const TOTAL_WEIGHT: int = 1000

## The wheel, clockwise from the top: {kind, amount, weight (per mille), steam_item (the token or,
## for the skin, its item), label}. Same-size slices; the odds are the weights.
const SEGMENTS: Array[Dictionary] = [
	{"kind": KIND_COINS, "amount": 100, "weight": 220, "steam_item": 3201},
	{"kind": KIND_GOLD, "amount": 5, "weight": 90, "steam_item": 3211},
	{"kind": KIND_COINS, "amount": 250, "weight": 160, "steam_item": 3203},
	{"kind": KIND_PIECE, "amount": 1, "weight": 100, "steam_item": 3207},
	{"kind": KIND_COINS, "amount": 1000, "weight": 55, "steam_item": 3205},
	{"kind": KIND_GOLD, "amount": 25, "weight": 20, "steam_item": 3213},
	{"kind": KIND_COINS, "amount": 150, "weight": 180, "steam_item": 3202},
	{"kind": KIND_SKIN, "amount": 1, "weight": 3, "steam_item": 208},
	{"kind": KIND_COINS, "amount": 500, "weight": 110, "steam_item": 3204},
	{"kind": KIND_GOLD, "amount": 10, "weight": 45, "steam_item": 3212},
	{"kind": KIND_COINS, "amount": 2500, "weight": 15, "steam_item": 3206},
	{"kind": KIND_GOLD, "amount": 50, "weight": 2, "steam_item": 3214},
]


## How many slices.
static func count() -> int:
	return SEGMENTS.size()


static func segment(i: int) -> Dictionary:
	return SEGMENTS[posmod(i, SEGMENTS.size())]


## Whether slice `i` can only be won through Steam (Gold Coins live in the Steam inventory, the
## Fortune skin too).
static func needs_steam(i: int) -> bool:
	var k: StringName = segment(i)["kind"]
	return k == KIND_GOLD or k == KIND_SKIN


## The slice a Steam item stands for (-1 = not a wheel prize).
static func index_of_item(def: int) -> int:
	for i: int in SEGMENTS.size():
		if int(SEGMENTS[i]["steam_item"]) == def:
			return i
	return -1


## The Gold Coin bundle a Gold token is exchanged for (0 = not a Gold token).
static func gold_bundle(token: int) -> int:
	var i: int = index_of_item(token)
	return token + GOLD_BUNDLE_OFFSET if i >= 0 and segment(i)["kind"] == KIND_GOLD else 0


## The chance of slice `i` with Steam (0..1).
static func chance(i: int) -> float:
	return float(segment(i)["weight"]) / float(TOTAL_WEIGHT)


## "0.3 %", "22 %".
static func chance_text(i: int) -> String:
	var pct: float = chance(i) * 100.0
	return ("%d %%" % roundi(pct)) if pct >= 1.0 else ("%.1f %%" % pct)


## The prize in words: "500 COINS", "10 GOLD", "MYSTERY PIECE", "FORTUNE SKIN".
static func label(i: int) -> String:
	var s: Dictionary = segment(i)
	match s["kind"]:
		KIND_COINS:
			return "%s COINS" % thousands(int(s["amount"]))
		KIND_GOLD:
			return "%d GOLD" % int(s["amount"])
		KIND_PIECE:
			return "MYSTERY PIECE"
		_:
			return "FORTUNE SKIN"


## Steam's generator list: "3201x220;3211x90;..." (for a generator the number is the weight).
static func generator_bundle() -> String:
	var parts := PackedStringArray()
	for s: Dictionary in SEGMENTS:
		parts.append("%dx%d" % [int(s["steam_item"]), int(s["weight"])])
	return ";".join(parts)


## The local roll (no Steam): a slice by the weights, the Steam-only slices left out. `r` is
## 0..1 (randf()).
static func roll_local(r: float) -> int:
	var total: int = 0
	for i: int in SEGMENTS.size():
		if not needs_steam(i):
			total += int(SEGMENTS[i]["weight"])
	var pick: float = clampf(r, 0.0, 0.999999) * float(total)
	for i: int in SEGMENTS.size():
		if needs_steam(i):
			continue
		pick -= float(SEGMENTS[i]["weight"])
		if pick < 0.0:
			return i
	return 0


## When the next spin is free (unix seconds) after a spin at `last` (0 = never spun). A clock
## turned forward to spin early and then back keeps the wheel shut until the real time has caught
## up with that spin and a full cooldown has passed; with Steam the time is Steam's anyway.
static func next_spin_at(last: int) -> int:
	return 0 if last <= 0 else last + COOLDOWN_S


## Seconds until the next spin (0 = spin now).
static func wait_s(last: int, now: int) -> int:
	return maxi(next_spin_at(last) - now, 0)


## "5 H 12 M", "12 M", "40 S".
static func wait_text(seconds: int) -> String:
	var s: int = maxi(seconds, 0)
	if s >= 3600:
		return "%d H %02d M" % [s / 3600, (s % 3600) / 60]
	if s >= 60:
		return "%d M" % ceili(s / 60.0)
	return "%d S" % s


## A random normal piece (bought with red Coins) this profile doesn't own yet, or &"" when every
## one is owned (the mystery piece then pays `PIECE_FALLBACK_COINS`). `r` is 0..1.
static func mystery_piece(p: PlayerProfile, r: float) -> StringName:
	var open: Array[StringName] = []
	for d: CosmeticDef in p.shop.items:
		if d.coin_buyable() and d.level <= 0 and not p.owns(d.id):
			open.append(d.id)
	if open.is_empty():
		return &""
	return open[clampi(int(r * open.size()), 0, open.size() - 1)]


## 2500 -> "2,500".
static func thousands(n: int) -> String:
	var t: String = str(absi(n))
	var out: String = ""
	while t.length() > 3:
		out = "," + t.substr(t.length() - 3) + out
		t = t.substr(0, t.length() - 3)
	return ("-" if n < 0 else "") + t + out
