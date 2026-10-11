class_name GrabYourHandLogic
extends WalkableLogicBase
## "Grab Your Hand" (MINIGAME_IDEAS #8), a walkable poker scramble in the card hall (`CardHall`).
##
## A server-shuffled 52-card deck feeds giant cards onto the floor at random spots: the floor keeps
## about `alive + EXTRA_ON_FLOOR` cards, and a card that is picked up is replaced `RESPAWN_DELAY` s
## later (while the deck lasts). Every card exists once: in the deck, on the floor or in one hand.
## For `GAME_SECONDS` everyone runs round collecting a poker hand:
## - **Pick up:** a bean whose centre comes within `PICK_REACH` (flat) of a floor card takes it;
##   checked every tick from the server's own positions, nearest bean first. A hand holds up to
##   `HAND_MAX` cards; a full hand walks over cards without taking them.
## - **Drop:** the action button, `minigame_action {kind: "drop", target?}` (target = hand slot,
##   default `PokerHand.worst_index`), lays that card on the floor `DROP_DISTANCE` in front of the
##   bean, where anyone can take it (the dropper only after `RELOCK_SECONDS`).
## - **Shove:** a shoved bean (`on_shoved`, called by the MatchServer when a shove lands) drops a
##   random card (seeded rng), flung `SHOVE_FLING` m away from the attacker. Grabbing is off.
## When the clock runs out the best poker hand wins (`PokerHand.evaluate`: category, then the
## ranks; with fewer than 5 cards pairs/trips/quads still count, straights and flushes need 5).
## Equal hands share a rank. Hands are public: the state carries everyone's cards.

enum State { PLAYING, REVEAL }

const GAME_SECONDS: float = 50.0
const HAND_MAX: int = 5
## Flat distance bean centre to card centre for a pickup.
const PICK_REACH: float = 0.8
## A bean's centre may be this far above/below a card and still take it (jumps, the dais step).
const PICK_HEIGHT: float = 1.4
## Cards on the floor = beans still in + this.
const EXTRA_ON_FLOOR: int = 3
## Seconds after the floor runs short before a new card lands.
const RESPAWN_DELAY: float = 2.0
## Fresh cards land at least this far from other floor cards and from beans.
const SPAWN_GAP: float = 1.4
## A dropped card lands this far in front of the dropper; a shoved card this far from the victim.
const DROP_DISTANCE: float = 1.4
const SHOVE_FLING: float = 1.8
## The one who let a card go can't take it back for this long (or they'd pick it up at once).
const RELOCK_SECONDS: float = 1.2
## Seconds the revealed hands stay up before the ranking.
const END_HOLD: float = 7.0

var state: State = State.PLAYING
var clock: float = 0.0
## The undealt cards; the next card is the back.
var deck: Array[int] = []
## floor id → {card, pos: Vector3, yaw, lock_player, lock_until}.
var floor_cards: Dictionary[int, Dictionary] = {}
## player → their cards in pickup order (the slot numbers of the hand UI).
var hands: Dictionary[int, Array] = {}
## Seconds left on each queued respawn.
var respawns: Array[float] = []
var wait_left: float = 0.0
## Fun stats: cards picked up and cards knocked out of others' hands.
var picked: Dictionary[int, int] = {}
var knocked: Dictionary[int, int] = {}
var _next_id: int = 1
var _announced: bool = false


func room_layout() -> Dictionary:
	return CardHall.layout()


func _on_room_setup(_context: Dictionary) -> void:
	id = &"grab_your_hand"
	for p: int in players:
		hands[p] = []
		picked[p] = 0
		knocked[p] = 0
	deck.clear()
	for c: int in 52:
		deck.append(c)
	rng.shuffle(deck)


## Grabbing is off: carrying a bean round would be a free hand thief. Shoving stays.
func blocked_intents() -> Array[StringName]:
	return [&"grab"]


func tick(delta: float, _now: float) -> void:
	if finished:
		return
	if not _announced:
		# The stage only exists after the curtain: start (and say so) on the first tick.
		_announced = true
		events.append(GameEvents.make(&"grab_your_hand_begin", {"seconds": GAME_SECONDS, "hand_max": HAND_MAX}))
		_spawn(target_on_floor() - floor_cards.size())
		return
	if state == State.REVEAL:
		wait_left -= delta
		if wait_left <= 0.0:
			_finish()
		return
	clock = minf(clock + delta, GAME_SECONDS)
	_pickups()
	_tick_respawns(delta)
	if clock >= GAME_SECONDS:
		_end_game()


## How many cards the floor keeps.
func target_on_floor() -> int:
	return alive.size() + EXTRA_ON_FLOOR


func hand_of(player: int) -> Array[int]:
	var out: Array[int] = []
	for c: Variant in hands.get(player, []):
		out.append(int(c))
	return out


func hand_rank(player: int) -> Array[int]:
	return PokerHand.evaluate(hands.get(player, []))


# --- Floor ----------------------------------------------------------------------------------------

func _tick_respawns(delta: float) -> void:
	var due: int = 0
	for i: int in range(respawns.size() - 1, -1, -1):
		respawns[i] -= delta
		if respawns[i] <= 0.0:
			respawns.remove_at(i)
			due += 1
	if due > 0:
		_spawn(mini(due, target_on_floor() - floor_cards.size()))
	var short: int = target_on_floor() - floor_cards.size() - respawns.size()
	for _i: int in maxi(short, 0):
		respawns.append(RESPAWN_DELAY)


## Deals `count` cards from the deck onto free floor spots.
func _spawn(count: int) -> void:
	var wire: Array = []
	for _i: int in count:
		if deck.is_empty():
			break
		var at: Vector3 = _free_spot()
		var f: Dictionary = _put_on_floor(deck.pop_back(), at, -1)
		wire.append(_floor_wire(int(f["id"])))
	if not wire.is_empty():
		events.append(GameEvents.make(&"grab_your_hand_spawned", {"cards": wire, "deck": deck.size()}))


## A random field spot clear of the other floor cards and of the beans (best of a few tries).
func _free_spot() -> Vector3:
	var best: Vector3 = Vector3.ZERO
	var best_gap: float = -1.0
	for _i: int in 12:
		var p: Vector3 = CardHall.random_spot(rng)
		var gap: float = INF
		for f: Dictionary in floor_cards.values():
			gap = minf(gap, _flat(p, f["pos"]))
		if world != null:
			for b: int in alive:
				if world.positions.has(b):
					gap = minf(gap, _flat(p, world.get_position(b)))
		if gap > best_gap:
			best_gap = gap
			best = p
		if gap >= SPAWN_GAP:
			break
	return best


func _put_on_floor(card: int, at: Vector3, locked_for: int) -> Dictionary:
	var fid: int = _next_id
	_next_id += 1
	var f: Dictionary = {"id": fid, "card": card, "pos": CardHall.clamp_to_field(at), "yaw": snappedf(rng.range_float(-PI, PI), 0.001), "lock_player": locked_for, "lock_until": clock + RELOCK_SECONDS}
	floor_cards[fid] = f
	return f


## Beans standing on cards take them, nearest first; a full hand skips.
func _pickups() -> void:
	if world == null or floor_cards.is_empty():
		return
	var hits: Array = []
	for fid: int in floor_cards:
		var f: Dictionary = floor_cards[fid]
		for p: int in alive:
			if not world.positions.has(p) or not hands.has(p):
				continue
			if int(f["lock_player"]) == p and clock < float(f["lock_until"]):
				continue
			var at: Vector3 = world.get_position(p)
			var card_pos: Vector3 = f["pos"]
			if absf(at.y - card_pos.y) > PICK_HEIGHT:
				continue
			var d: float = _flat(at, card_pos)
			if d <= PICK_REACH:
				hits.append([d, p, fid])
	hits.sort_custom(func(a: Array, b: Array) -> bool: return float(a[0]) < float(b[0]) if float(a[0]) != float(b[0]) else int(a[1]) < int(b[1]))
	for h: Array in hits:
		var p: int = int(h[1])
		var fid: int = int(h[2])
		if floor_cards.has(fid) and (hands[p] as Array).size() < HAND_MAX:
			_take(p, fid)


func _take(player: int, fid: int) -> void:
	var f: Dictionary = floor_cards[fid]
	floor_cards.erase(fid)
	(hands[player] as Array).append(int(f["card"]))
	picked[player] = int(picked.get(player, 0)) + 1
	var t: Array[int] = hand_rank(player)
	events.append(GameEvents.make(&"grab_your_hand_picked", {
		"player": player, "id": fid, "card": int(f["card"]), "hand": hand_of(player), "name": PokerHand.name_of(t),
	}))


## Takes card `slot` out of `player`'s hand and lays it at `at` (the dropper can't retake it for a
## moment). Returns the floor id.
func _drop(player: int, slot: int, at: Vector3, how: StringName, attacker: int = -1) -> int:
	var hand: Array = hands[player]
	var card: int = int(hand[slot])
	hand.remove_at(slot)
	var f: Dictionary = _put_on_floor(card, at, player)
	var ev: Dictionary = _floor_wire(int(f["id"]))
	ev["player"] = player
	ev["slot"] = slot
	ev["how"] = how
	ev["attacker"] = attacker
	ev["from"] = Serializer.vec3(world.get_position(player)) if world != null and world.positions.has(player) else ev["pos"]
	ev["hand"] = hand_of(player)
	ev["name"] = PokerHand.name_of(hand_rank(player))
	events.append(GameEvents.make(&"grab_your_hand_dropped", ev))
	return int(f["id"])


# --- Actions ------------------------------------------------------------------------------------

## The action button: kind "drop", target = hand slot (default: the worst card).
func _on_action(player: int, kind: StringName, hint: int, _now: float) -> Dictionary:
	if kind != &"drop":
		return StationLogicBase.fail(&"bad_value")
	if state != State.PLAYING:
		return StationLogicBase.fail(&"game_over")
	var hand: Array = hands.get(player, [])
	if hand.is_empty():
		return StationLogicBase.fail(&"empty_hand")
	var slot: int = hint if hint >= 0 and hint < hand.size() else PokerHand.worst_index(hand)
	var at: Vector3 = spawn_for(player)
	var facing: Vector3 = Vector3.FORWARD
	if world != null and world.positions.has(player):
		at = world.get_position(player)
		facing = world.get_facing(player)
	facing.y = 0.0
	facing = facing.normalized() if facing.length() > 0.01 else Vector3.FORWARD
	var card: int = int(hand[slot])
	var fid: int = _drop(player, slot, at + facing * DROP_DISTANCE, &"drop")
	return {"ok": true, "error": &"", "card": card, "id": fid}


## A shove landed on `target` (the MatchServer calls this after the shove resolves): they drop a
## random card, flung away from the attacker.
func on_shoved(target: int, attacker: int) -> void:
	if state != State.PLAYING or finished or not _announced or target not in alive:
		return
	var hand: Array = hands.get(target, [])
	if hand.is_empty():
		return
	var slot: int = rng.range_int(0, hand.size() - 1)
	var at: Vector3 = spawn_for(target)
	var dir: Vector3 = Vector3.BACK
	if world != null and world.positions.has(target):
		at = world.get_position(target)
		if world.positions.has(attacker):
			dir = at - world.get_position(attacker)
	dir.y = 0.0
	dir = dir.normalized() if dir.length() > 0.01 else Vector3.BACK
	knocked[attacker] = int(knocked.get(attacker, 0)) + 1
	_drop(target, slot, at + dir * SHOVE_FLING, &"shove", attacker)


# --- End ----------------------------------------------------------------------------------------

## A dropout's cards go back into the deck (shuffled in), so they can come back on the floor.
func remove_player(player: int) -> void:
	for c: Variant in hands.get(player, []):
		deck.insert(rng.range_int(0, deck.size()), int(c))
	hands.erase(player)
	super.remove_player(player)
	if not finished and _announced and state == State.PLAYING and alive.size() < 2:
		_end_game()


func _end_game() -> void:
	if state == State.REVEAL:
		return
	state = State.REVEAL
	wait_left = END_HOLD
	events.append(GameEvents.make(&"grab_your_hand_over", {"hands": _hands_wire(), "names": _names_wire(), "ranking": ranking()}))


func _finish() -> void:
	finished = true
	events.append(GameEvents.make(&"grab_your_hand_finished", {"ranking": ranking()}))


## Best poker hand first; equal hands (same rank tuple) share a rank. `points` = players beaten.
func ranking() -> Array[Dictionary]:
	var order: Array[int] = []
	var tuples: Dictionary[int, Array] = {}
	for p: int in players:
		order.append(p)
		tuples[p] = PokerHand.evaluate(hands.get(p, []))
	order.sort_custom(func(a: int, b: int) -> bool:
		var cmp: int = PokerHand.compare(tuples[a], tuples[b])
		return cmp > 0 if cmp != 0 else a < b)
	var out: Array[Dictionary] = []
	var rank: int = 1
	for i: int in order.size():
		var p: int = order[i]
		if i > 0 and PokerHand.compare(tuples[p], tuples[order[i - 1]]) != 0:
			rank = i + 1
		var beaten: int = 0
		for q: int in order:
			if PokerHand.compare(tuples[p], tuples[q]) > 0:
				beaten += 1
		out.append({"player": p, "points": beaten, "rank": rank, "hand": hand_of(p), "name": PokerHand.name_of(tuples[p]), "describe": PokerHand.describe(tuples[p])})
	return out


func get_public_state() -> Dictionary:
	var st: Dictionary = walkable_state()
	st["state"] = String(State.keys()[state]).to_lower()
	st["clock"] = snappedf(clock, 0.01)
	st["seconds"] = GAME_SECONDS
	st["hand_max"] = HAND_MAX
	var fl: Array = []
	for fid: int in floor_cards:
		fl.append(_floor_wire(fid))
	st["floor"] = fl
	st["hands"] = _hands_wire()
	st["names"] = _names_wire()
	st["deck"] = deck.size()
	if finished or state == State.REVEAL:
		st["ranking"] = ranking()
	return st


func _floor_wire(fid: int) -> Dictionary:
	var f: Dictionary = floor_cards[fid]
	return {"id": fid, "card": int(f["card"]), "pos": Serializer.vec3(f["pos"]), "yaw": float(f["yaw"])}


func _hands_wire() -> Dictionary:
	var out: Dictionary = {}
	for p: int in hands:
		out[p] = hand_of(p)
	return out


func _names_wire() -> Dictionary:
	var out: Dictionary = {}
	for p: int in hands:
		out[p] = PokerHand.name_of(hand_rank(p))
	return out


static func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()
