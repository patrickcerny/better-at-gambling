class_name ClientMatchState
extends RefCounted
## Client-side mirror of the replicated match state, rebuilt from snapshots and events. UI reads
## this, never the server.

signal money_changed(player: int, amount: int, balance: int, reason: StringName)
signal phase_changed(phase: Phase.Id)
signal station_changed(station_id: StringName)
signal players_changed
signal feed_message(text: String, kind: StringName)
## Lobby data changed (leader, settings, countdown, ready, cosmetics).
signal lobby_changed
## The Hot Table moved ("" = none).
signal hot_table_changed(station: StringName)
## Results arrived (standings + awards).
signal results_changed
## Item effects on a player changed (public: item ids only).
signal effects_changed(player: int)
## Banana peels appeared or disappeared.
signal peels_changed
## The Gift Shop got new stock.
signal shop_changed
## Waiter puddles or the Megaphone holder changed (M7).
signal floor_changed

var phase: Phase.Id = Phase.Id.LOBBY
var casino_time: float = 0.0
var time_left: float = 0.0
var next_minigame_in: float = -1.0
var segment_index: int = 0
var last_call: bool = false
var duration_minutes: int = 10
var players: Dictionary[int, Dictionary] = {}
var balances: Dictionary[int, int] = {}
var stations: Dictionary = {}
var jackpot: int = 0
var last_seq: int = 0
var piles: Dictionary[int, Dictionary] = {}
var standings: Array = []
## Seated station of each player.
var seat_of: Dictionary[int, StringName] = {}
## Online lobby: party leader, host settings, start countdown (-1 = none), room or Practice.
var leader: int = -1
var lobby_settings: Dictionary = {}
var countdown: float = -1.0
var room_mode: bool = false
## Hot Table: station id ("" = none) and seconds left (counted down locally between snapshots).
var hot_station: StringName = &""
var hot_left: float = 0.0
## Minigame public state from the last snapshot (a view joining mid-minigame starts from it).
var minigame: Dictionary = {}
## Reward phase summary [{player, placement, cash, draft, bonus_count}].
var rewards: Array = []
var awards: Array = []
## Online results screen: seconds until the room goes back to its lobby (-1 = never).
var results_return_in: float = -1.0
## Active item effects per player (item ids, public) and banana peels on the floor (peel id →
## {peel, owner, pos, seconds}).
var effects: Dictionary[int, Array] = {}
var peels: Dictionary[int, Dictionary] = {}
## Gift Shop offers this segment [{item, price, rarity}].
var shop_offers: Array = []
## Drink puddles the waiter spilled (puddle id → {puddle, pos, seconds}) and the player holding
## the Megaphone (-1: on its stand).
var puddles: Dictionary[int, Dictionary] = {}
var megaphone_holder: int = -1


## Replaces everything from a snapshot.
func apply_snapshot(snap: Dictionary) -> void:
	phase = int(snap.get("phase", 0)) as Phase.Id
	casino_time = float(snap.get("casino_time", 0.0))
	time_left = float(snap.get("time_left", 0.0))
	next_minigame_in = float(snap.get("next_minigame_in", -1.0))
	segment_index = int(snap.get("segment", 0))
	last_call = bool(snap.get("last_call", false))
	duration_minutes = int(snap.get("duration", 10))
	players.clear()
	seat_of.clear()
	for id: Variant in snap.get("players", {}):
		players[int(id)] = snap["players"][id]
		seat_of[int(id)] = StringName(snap["players"][id].get("station", ""))
	balances.clear()
	for id: Variant in snap.get("balances", {}):
		balances[int(id)] = int(snap["balances"][id])
	stations = (snap.get("stations", {}) as Dictionary).duplicate(true)
	jackpot = int(snap.get("jackpot", 0))
	last_seq = int(snap.get("seq", 0))
	piles.clear()
	for p: Dictionary in snap.get("piles", []):
		piles[int(p["pile"])] = p
	var lobby: Dictionary = snap.get("lobby", {})
	leader = int(lobby.get("leader", -1))
	lobby_settings = lobby.get("settings", {})
	countdown = float(lobby.get("countdown", -1.0))
	room_mode = bool(snap.get("room", false))
	var hot: Dictionary = snap.get("hot_table", {})
	hot_station = StringName(hot.get("station", ""))
	hot_left = float(hot.get("time_left", 0.0))
	minigame = snap.get("minigame", {})
	rewards = (snap.get("rewards", {}) as Dictionary).get("rewards", [])
	standings = snap.get("standings", [])
	awards = snap.get("awards", [])
	results_return_in = float(snap.get("results_return_in", -1.0))
	effects.clear()
	for id: Variant in snap.get("effects", {}):
		effects[int(id)] = (snap["effects"][id] as Array).duplicate()
	shop_offers = (snap.get("shop", {}) as Dictionary).get("offers", []).duplicate(true)
	shop_changed.emit()
	peels.clear()
	for p: Dictionary in snap.get("peels", []):
		peels[int(p["peel"])] = p
	var floor_state: Dictionary = snap.get("floor", {})
	puddles.clear()
	for p: Dictionary in floor_state.get("puddles", []):
		puddles[int(p["puddle"])] = p
	megaphone_holder = int((floor_state.get("megaphone", {}) as Dictionary).get("holder", -1))
	floor_changed.emit()
	if phase == Phase.Id.LOBBY:
		last_call = false
	players_changed.emit()
	hot_table_changed.emit(hot_station)
	peels_changed.emit()
	for id: int in players:
		effects_changed.emit(id)
	lobby_changed.emit()
	phase_changed.emit(phase)
	for sid: Variant in stations:
		station_changed.emit(StringName(sid))


## Applies one event. Returns false if a sequence gap was detected (caller should resnapshot).
func apply_event(ev: Dictionary) -> bool:
	if ev.has("seq") and int(ev["seq"]) <= last_seq:
		return true  # already in the snapshot we applied
	var seq: int = int(ev.get("seq", last_seq))
	var gap: bool = seq > last_seq + 1 and last_seq > 0
	last_seq = maxi(last_seq, seq)
	var type: StringName = ev["type"]
	match type:
		&"player_joined":
			var p: Dictionary = ev["player"]
			players[int(p["id"])] = p
			players_changed.emit()
		&"phase_changed":
			phase = int(ev["phase"]) as Phase.Id
			casino_time = float(ev.get("casino_time", casino_time))
			segment_index = int(ev.get("segment", segment_index))
			phase_changed.emit(phase)
		&"last_call":
			last_call = true
			feed_message.emit("LAST CALL! All winnings ×%.1f" % float(ev["multiplier"]), &"last_call")
		&"money_changed":
			balances[int(ev["player"])] = int(ev["balance"])
			money_changed.emit(int(ev["player"]), int(ev["amount"]), int(ev["balance"]), StringName(ev["reason"]))
		&"player_sat":
			seat_of[int(ev["player"])] = StringName(ev["station"])
			if players.has(int(ev["player"])):
				players[int(ev["player"])]["seat"] = int(ev.get("seat", -1))
			players_changed.emit()
		&"player_stood":
			seat_of[int(ev["player"])] = &""
			players_changed.emit()
		&"round_result":
			var net: int = int(ev["net"])
			if net != 0:
				feed_message.emit("%s %s$%d at %s" % [player_name(int(ev["player"])), "+" if net > 0 else "−", absi(net), station_label(StringName(ev["station"]))], &"win" if net > 0 else &"loss")
		&"jackpot_won":
			feed_message.emit("%s hit the JACKPOT for $%d!" % [player_name(int(ev["player"])), int(ev["amount"])], &"jackpot")
		&"jackpot_changed":
			jackpot = int(ev["amount"])
		&"chips_dropped":
			piles[int(ev["pile"])] = ev
		&"chips_collected", &"pickup_expired":
			piles.erase(int(ev["pile"]))
		&"player_knocked_out":
			feed_message.emit("%s got knocked out!" % player_name(int(ev["target"])), &"chaos")
		&"chips_shaken_out":
			feed_message.emit("%s shook $%d out of %s" % [player_name(int(ev["attacker"])), int(ev["amount"]), player_name(int(ev["target"]))], &"chaos")
		&"player_thrown_out":
			feed_message.emit("Security threw %s out!" % player_name(int(ev["target"])), &"chaos")
		&"player_ready":
			if players.has(int(ev["player"])):
				players[int(ev["player"])]["ready"] = bool(ev["ready"])
			lobby_changed.emit()
		&"player_skin":
			if players.has(int(ev["player"])):
				players[int(ev["player"])]["skin"] = StringName(ev["skin"])
			players_changed.emit()
			lobby_changed.emit()
		&"leader_changed":
			leader = int(ev["player"])
			lobby_changed.emit()
		&"lobby_settings":
			lobby_settings = ev["settings"]
			lobby_changed.emit()
		&"lobby_countdown":
			countdown = float(ev["seconds"])
			lobby_changed.emit()
		&"lobby_countdown_cancelled":
			countdown = -1.0
			lobby_changed.emit()
		&"player_left", &"player_rejoined":
			if players.has(int(ev["player"])):
				players[int(ev["player"])]["connected"] = ev["type"] == &"player_rejoined"
				if ev["type"] == &"player_left":
					players[int(ev["player"])]["ready"] = false
			feed_message.emit("%s %s" % [player_name(int(ev["player"])), "lost connection" if ev["type"] == &"player_left" else "is back"], &"info")
			players_changed.emit()
			lobby_changed.emit()
		&"player_removed":
			players.erase(int(ev["player"]))
			balances.erase(int(ev["player"]))
			players_changed.emit()
			lobby_changed.emit()
		&"match_started":
			duration_minutes = int(ev["duration"])
			countdown = -1.0
		&"match_ended":
			standings = ev["standings"]
			awards = ev.get("awards", [])
			results_return_in = float(ev.get("return_in", -1.0))
			phase = Phase.Id.RESULTS
			hot_station = &""
			hot_table_changed.emit(hot_station)
			phase_changed.emit(phase)
			results_changed.emit()
		&"hot_table":
			hot_station = StringName(ev["station"])
			hot_left = float(ev["seconds"])
			feed_message.emit("%s is HOT! Winnings ×%.2f for %ds" % [station_label(hot_station), float(ev["multiplier"]), int(ev["seconds"])], &"hot")
			hot_table_changed.emit(hot_station)
		&"hot_table_ended":
			if hot_station == StringName(ev["station"]):
				hot_station = &""
				hot_table_changed.emit(hot_station)
		&"house_comp":
			feed_message.emit("The house feels sorry for %s: +$%d" % [player_name(int(ev["player"])), int(ev["amount"])], &"comp")
		&"minigame_started":
			minigame = {"minigame": ev["minigame"], "state": 0}
		&"minigame_finished":
			minigame = {}
		&"rewards_started":
			rewards = ev["rewards"]
		&"draft_result":
			var pid: int = int(ev["player"])
			if players.has(pid):
				players[pid]["inventory"] = ev.get("inventory", [])
			players_changed.emit()
		&"inventory_changed":
			var pid: int = int(ev["player"])
			if players.has(pid):
				players[pid]["inventory"] = ev["inventory"]
			players_changed.emit()
		&"item_used":
			_on_item_used(ev)
		&"effect_ended":
			var pid: int = int(ev["player"])
			var list: Array = effects.get(pid, [])
			list.erase(StringName(ev["item"]))
			effects_changed.emit(pid)
		&"monkey_passed":
			var from: int = int(ev["from"])
			var to: int = int(ev["to"])
			(effects.get(from, []) as Array).erase(StringName(ev["item"]))
			if not effects.has(to):
				effects[to] = []
			effects[to].append(StringName(ev["item"]))
			effects_changed.emit(from)
			effects_changed.emit(to)
			feed_message.emit("%s passed the Bad Luck Monkey to %s" % [player_name(from), player_name(to)], &"chaos")
		&"fake_cash_caught":
			feed_message.emit("The bouncer caught %s with fake cash (−$%d)" % [player_name(int(ev["player"])), int(ev["fine"])], &"chaos")
		&"credit_repaid":
			feed_message.emit("The bank collected $%d from %s" % [int(ev["amount"]), player_name(int(ev["player"]))], &"loss")
		&"bodyguard_saved":
			feed_message.emit("%s's Bodyguard stepped in!" % player_name(int(ev["player"])), &"chaos")
		&"banana_placed":
			peels[int(ev["peel"])] = ev
			peels_changed.emit()
		&"banana_removed":
			peels.erase(int(ev["peel"]))
			peels_changed.emit()
		&"banana_slip":
			var victim: int = int(ev["victim"])
			match StringName(ev["result"]):
				&"blocked":
					feed_message.emit("%s's Bodyguard kicked a banana peel away" % player_name(int(ev["player"])), &"chaos")
				&"reflected":
					feed_message.emit("%s's Mirror sent the banana back: %s slipped (−$%d)" % [player_name(int(ev["player"])), player_name(victim), int(ev["amount"])], &"chaos")
				_:
					feed_message.emit("%s slipped on a banana (−$%d)" % [player_name(victim), int(ev["amount"])], &"chaos")
		&"shop_restocked":
			shop_offers = (ev["offers"] as Array).duplicate(true)
			shop_changed.emit()
		&"shop_bought":
			feed_message.emit("%s bought %s at the Gift Shop" % [player_name(int(ev["player"])), RewardPanel.item_name(StringName(ev["item"]))], &"item")
		&"rps_result":
			if not bool(ev["replay"]):
				var w: int = int(ev["winner"])
				if w < 0:
					feed_message.emit("%s and %s tied at Rock Paper Scissors twice: no money changed hands" % [player_name(int(ev["a"])), player_name(int(ev["b"]))], &"item")
				else:
					var l: int = int(ev["b"]) if w == int(ev["a"]) else int(ev["a"])
					feed_message.emit("%s beat %s at Rock Paper Scissors (+$%d)" % [player_name(w), player_name(l), int(ev["amount"])], &"chaos")
		&"waiter_tripped":
			puddles[int(ev["puddle"])] = {"puddle": ev["puddle"], "pos": ev["puddle_pos"], "seconds": ev["seconds"]}
			floor_changed.emit()
			if int(ev["player"]) >= 0:
				feed_message.emit("%s knocked the waiter over. Wet floor!" % player_name(int(ev["player"])), &"chaos")
			else:
				feed_message.emit("The waiter tripped. Wet floor!", &"chaos")
		&"puddle_removed":
			puddles.erase(int(ev["puddle"]))
			floor_changed.emit()
		&"puddle_slip":
			feed_message.emit("%s slipped in a puddle" % player_name(int(ev["player"])), &"chaos")
		&"megaphone_taken":
			megaphone_holder = int(ev["player"])
			floor_changed.emit()
			feed_message.emit("%s grabbed the megaphone!" % player_name(megaphone_holder), &"chaos")
		&"megaphone_dropped":
			megaphone_holder = -1
			floor_changed.emit()
		&"match_reset":
			puddles.clear()
			megaphone_holder = -1
			floor_changed.emit()
			effects.clear()
			peels.clear()
			peels_changed.emit()
			phase = Phase.Id.LOBBY
			last_call = false
			standings = []
			awards = []
			results_return_in = -1.0
			phase_changed.emit(phase)
	if ev.has("station") and stations.has(ev["station"]):
		station_changed.emit(StringName(ev["station"]))
	return not gap


func _on_item_used(ev: Dictionary) -> void:
	var user: int = int(ev["player"])
	var item: StringName = StringName(ev["item"])
	var target: int = int(ev["target"])
	var result: StringName = StringName(ev["result"])
	var def: ItemDefinition = Registry.items.get(item, null) if Registry.items != null else null
	var name: String = def.display_name if def != null else String(item).capitalize()
	if ev.has("affected") and result != &"blocked":
		var who: int = int(ev.get("affected", target))
		if not effects.has(who):
			effects[who] = []
		if not effects[who].has(item):
			effects[who].append(item)
		effects_changed.emit(who)
	var text: String
	if target == user or target < 0:
		text = "%s used %s" % [player_name(user), name]
	else:
		text = "%s used %s on %s" % [player_name(user), name, player_name(target)]
	match result:
		&"blocked":
			text += ", but the Bodyguard blocked it"
		&"reflected":
			text += ", but the Mirror bounced it back"
	match item:
		&"scratch_ticket":
			text += ": $%d!" % int(ev.get("amount", 0)) if ev.get("prize", &"") == &"cash" else ": %s" % RewardPanel.item_name(StringName(ev.get("won_item", "")))
		&"russian_roulette":
			text += ": BANG! (−$%d)" % int(ev.get("amount", 0)) if bool(ev.get("bang", false)) else ": *click* (+$%d)" % int(ev.get("amount", 0))
		&"credit_card":
			text += " (+$%d)" % int(ev.get("loan", 0))
		&"out_of_order":
			text += " on %s" % station_label(StringName(ev.get("station", "")))
		&"rock_paper_scissors":
			text += " for $%d" % int(ev.get("stake", 0))
		_:
			if bool(ev.get("caught", false)):
				text += ", but got caught and paid $%d" % int(ev.get("paid", 0))
			elif ev.has("amount") and int(ev["amount"]) > 0:
				text += " (−$%d)" % int(ev["amount"])
	feed_message.emit(text, &"item")


## "Blackjack 2" from "blackjack_2".
static func station_label(sid: StringName) -> String:
	var parts: PackedStringArray = String(sid).split("_")
	if parts.size() >= 2 and parts[-1].is_valid_int():
		return "%s %s" % [" ".join(parts.slice(0, parts.size() - 1)).capitalize(), parts[-1]]
	return String(sid).capitalize()


## Display name of a player.
func player_name(id: int) -> String:
	return str(players.get(id, {}).get("name", "Player %d" % id))


## Balance of a player.
func balance(id: int) -> int:
	return balances.get(id, 0)


## Rank (1-based) of a player by money.
func rank_of(id: int) -> int:
	var mine: int = balance(id)
	var rank: int = 1
	for other: int in balances:
		if other != id and balances[other] > mine:
			rank += 1
	return rank
