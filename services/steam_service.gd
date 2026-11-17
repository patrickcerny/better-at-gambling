extends Node
## `SteamSvc` autoload: the game's door to Steam through the GodotSteam GDExtension
## (addons/godotsteam). The autoload is named `SteamSvc`, not `Steam`, because GodotSteam registers
## an engine singleton called `Steam` (docs/DECISIONS.md).
##
## Steam is needed to play online: every party is a Steam lobby hosted on a player's PC, friends join
## through the Steam relay (App ID 5623410, the game's own; Practice works without Steam).
## Without a Steam client (the headless tests, the dedicated server, `--no-steam`, a PC
## without Steam) `is_available()` is false, nothing else is called and one info line says why.
##
## Lobbies: the host's party is a friends-only Steam lobby carrying {game, build, name}; friends
## join it from the overlay invite or "Join game" in their friends list (`join_requested`), or the
## game is launched with `+connect_lobby <id>` (Steam starts it that way when it wasn't running).
## The lobby owner's Steam ID is where the joiner connects (`SteamTransport`).

## A friend chose "Join game" / accepted an invite (or the game was launched to join a lobby).
signal join_requested(lobby_id: int)
## `create_lobby` finished: the lobby id, or 0 with `last_error` set.
signal lobby_ready(lobby_id: int)
## `join_lobby` finished: {lobby_id, owner, ok, error}.
signal lobby_entered(result: Dictionary)
## Someone entered or left our lobby.
signal lobby_members_changed(lobby_id: int)
## The Steam inventory or the real-money prices changed (the shop redraws).
signal store_changed
## A purchase ended: ok (paid, the inventory follows) or not (cancelled or failed).
signal purchase_finished(ok: bool)
## A Gold Coin purchase (exchange) ended: ok (the piece or set is in the inventory) or not.
signal gold_spent(ok: bool)
## The Daily Spin's item drop came back (`daily_spin`): {ok, index (the wheel slice won, -1 when
## Steam gave nothing: the spin isn't ready on Steam yet)}.
signal daily_spun(result: Dictionary)
## A Daily Spin prize was paid out: {index, coins (red Coins added), piece (a mystery piece's id or
## &""), gold (Gold Coins added)}.
signal daily_redeemed(prize: Dictionary)
## `request_public_lobbies` finished: [{lobby, name, members, max}] (BROWSE LOBBIES).
signal public_lobbies_received(lobbies: Array[Dictionary])

## The game's own Steamworks App ID (was 480 "Spacewar" for tests until 0.9.16).
const APP_ID: int = 5623410
const LOBBY_GAME: String = "better_at_gambling"
## PRIVATE lobbies: only Steam friends (FRIENDS' LOBBIES) and invited players get in.
const LOBBY_TYPE_FRIENDS_ONLY: int = 1
## PUBLIC lobbies: also listed under BROWSE LOBBIES for everyone on the same version.
const LOBBY_TYPE_PUBLIC: int = 2
const LOBBY_COMPARISON_EQUAL: int = 0
const LOBBY_DISTANCE_FILTER_WORLDWIDE: int = 3
## At most this many lobbies under BROWSE LOBBIES.
const PUBLIC_LOBBY_LIMIT: int = 50
const CHAT_ROOM_ENTER_RESPONSE_SUCCESS: int = 1
const FRIEND_FLAG_IMMEDIATE: int = 4

## The GodotSteam singleton (null when the extension is missing).
var steam: Object = null
## Lobby we are in (0 = none) and whether we own it.
var lobby_id: int = 0
var lobby_owner: bool = false
## The `LobbyInfo` text last written to our lobby (only changes are sent to Steam).
var _info_sent: String = ""
## A lobby to join that arrived before anyone could act on it (launch argument, or a join request
## while a match was loading). The main menu picks it up.
var pending_lobby: int = 0
var last_error: String = ""

var _available: bool = false
## Seconds until a changed look goes up (0 = nothing waiting), and the wait after a change.
var _look_wait: float = 0.0
const LOOK_DELAY: float = 4.0
## The look `submit_profile_bests` last uploaded this run.
var _bests_look: PackedInt32Array = PackedInt32Array()
## The global leaderboards (`SteamLeaderboards`; a no-op without Steam).
var boards: SteamLeaderboards = SteamLeaderboards.new()
var _steam_id: int = 0
var _persona: String = ""
## Achievements already handed to Steam this run (asked once each).
var _unlocked: Array[StringName] = []
## Beat the Dev: players we beat whose achievements Steam is still fetching.
var _beat_pending: Array[int] = []
## Real-money store (Steam Inventory Service): the player's currency ("" until Steam answers) and
## each item definition's price in that currency's smallest unit.
var currency: String = ""
var prices: Dictionary[int, int] = {}
## A purchase is waiting for the overlay.
var buying: bool = false
## Gold Coins in the Steam inventory (`CoinPack.GOLD_ITEM` stacks added up).
var gold: int = 0
## The Gold Coin stacks: [{item_id, quantity}] (what an exchange spends from).
var _gold_stacks: Array[Dictionary] = []
## Exchanges on their way: result handle -> the item definition bought.
var _exchanging: Dictionary[int, int] = {}
## The Daily Spin's item drop on its way (its result handle, 0 = none).
var _dropping: int = 0
## Wheel prize tokens being redeemed: result handle -> {item_id, def, quantity}, and the token
## item ids on their way (never redeemed twice at once).
var _redeeming: Dictionary[int, Dictionary] = {}
var _redeem_items: Array[int] = []
## A public lobby list request is on its way.
var browsing: bool = false
var _browse_started: int = 0
## A list request Steam never answered stops blocking new ones after this long.
const BROWSE_TIMEOUT_MS: int = 15000


func _ready() -> void:
	pending_lobby = _launch_lobby(OS.get_cmdline_args())
	var why: String = _skip_reason()
	if why != "":
		Log.info(&"steam", "Steam off: %s" % why)
		return
	steam = Engine.get_singleton("Steam")
	if not bool(steam.call("isSteamRunning")):
		Log.info(&"steam", "Steam off: the Steam client is not running")
		steam = null
		return
	var res: Dictionary = steam.call("steamInitEx", APP_ID, false)
	if int(res.get("status", 1)) != 0:
		Log.info(&"steam", "Steam off: %s" % str(res.get("verbal", "init failed")))
		steam = null
		return
	_available = true
	_steam_id = int(steam.call("getSteamID"))
	_persona = str(steam.call("getPersonaName"))
	steam.call("initRelayNetworkAccess")  # warm up the relay network before anyone hosts or joins
	steam.connect(&"join_requested", _on_join_requested)
	steam.connect(&"lobby_created", _on_lobby_created)
	steam.connect(&"lobby_joined", _on_lobby_joined)
	steam.connect(&"lobby_chat_update", _on_lobby_chat_update)
	steam.connect(&"lobby_match_list", _on_lobby_match_list)
	steam.connect(&"user_stats_received", _on_user_stats_received)
	if steam.has_method(&"isSteamRunningOnSteamDeck") and bool(steam.call("isSteamRunningOnSteamDeck")):
		InputGlyphs.set_deck(true)
	Log.info(&"steam", "Steam on: %s (app %d)" % [_persona, APP_ID])
	boards = SteamLeaderboards.new(steam)
	_start_store()
	# Lifetime achievements follow the profile (level-ups, matches, the shop) and catch up on start.
	ProfileManager.changed.connect(_on_profile_changed)
	_on_profile_changed()
	# The developers own every achievement (`DevMode.granted_achievements`), set once per start.
	unlock_achievements(DevMode.granted_achievements(_steam_id))
	sync_achievements()
	submit_profile_bests()


func _process(delta: float) -> void:
	if _available:
		steam.call("run_callbacks")
		if _look_wait > 0.0:
			_look_wait -= delta
			if _look_wait <= 0.0:
				submit_profile_bests()


func _exit_tree() -> void:
	if _available:
		leave_lobby()
		steam.call("steamShutdown")
		_available = false


## Unlocks Steam achievements by API name (`Achievements.DEFS`) and stores them once. Without
## Steam nothing happens. Returns the ones newly unlocked this call.
func unlock_achievements(ids: Array[StringName]) -> Array[StringName]:
	var fresh: Array[StringName] = []
	if not _available or ids.is_empty() or DevMode.used:
		return fresh  # developer mode was used this run: nothing it did may earn an achievement
	for id: StringName in ids:
		if id in _unlocked:
			continue
		_unlocked.append(id)
		var have: Dictionary = steam.call("getAchievement", String(id))
		if bool(have.get("achieved", false)):
			continue
		if bool(steam.call("setAchievement", String(id))):
			fresh.append(id)
		else:
			Log.warn(&"steam", "achievement %s is not set up in Steamworks" % id)
	if not fresh.is_empty():
		steam.call("storeStats")
		Log.info(&"steam", "achievements unlocked: %s" % ", ".join(fresh))
		sync_achievements()
	return fresh


## Tells the profile which achievements this account holds, so their rewards (`CosmeticDef.
## achievement`) can be collected in the shop, also ones earned before the rewards existed.
func sync_achievements() -> void:
	if not _available:
		return
	var held: Array[StringName] = []
	for d: CosmeticDef in ProfileManager.profile.shop.items:
		if d.achievement != &"" and not d.achievement in held:
			var have: Variant = steam.call("getAchievement", String(d.achievement))
			if have is Dictionary and bool((have as Dictionary).get("achieved", false)):
				held.append(d.achievement)
	ProfileManager.note_achieved(held)


## Beat the Dev (`Achievements.BEAT_THE_DEV`): `beaten` are the Steam IDs of the players the local
## player finished ahead of. One of them is the developer → unlocked now; otherwise their stats are
## requested from Steam and it unlocks if one of them already holds it (`_on_user_stats_received`).
func check_beat_the_dev(beaten: Array[int]) -> void:
	if not _available or beaten.is_empty() or DevMode.used or Achievements.BEAT_THE_DEV in _unlocked:
		return
	if bool((steam.call("getAchievement", String(Achievements.BEAT_THE_DEV)) as Dictionary).get("achieved", false)):
		_unlocked.append(Achievements.BEAT_THE_DEV)
		return
	for sid: int in beaten:
		if DevMode.is_the_dev(sid):
			unlock_achievements([Achievements.BEAT_THE_DEV])
			return
	for sid: int in beaten:
		if sid != _steam_id and not sid in _beat_pending:
			_beat_pending.append(sid)
			steam.call("requestUserStats", sid)


## After a match: the local player's ranked row (`MatchServer.progress_rows`, already added to the
## profile) goes on the global leaderboards (`LeaderboardRules.scores_for`). Nothing when the host
## didn't rank the match. The developer mode doesn't block it any more (Patrick 2026-11-16: "why
## am i not on the leaderboard"): its menu tools (Coins, levels, cosmetics) can't touch an online
## match's money, and its in-match tools only work in Practice, which the host never ranks.
func submit_match(row: Dictionary) -> void:
	if not _available:
		return
	boards.submit(LeaderboardRules.scores_for(row, ProfileManager.profile), my_look())


## The local player's bean colour and outfit as leaderboard details (`LeaderboardRules.skin_details`).
func my_look() -> PackedInt32Array:
	var p: PlayerProfile = ProfileManager.profile
	return LeaderboardRules.skin_details(p.preferred_color if p.preferred_color >= 0 else 0, p.outfit_wire())


## On start: the profile's ranked bests (`LeaderboardRules.profile_scores`) go up again. Steam
## keeps the higher score, so this only fills in matches whose upload never happened (an earlier
## run with the developer mode on, Steam offline when the match ended).
## Also when the leaderboards open, so a new outfit shows there at once (once per look and run).
func submit_profile_bests() -> void:
	if not _available:
		return
	var look: PackedInt32Array = my_look()
	if look == _bests_look:
		return
	_bests_look = look
	boards.submit(LeaderboardRules.profile_scores(ProfileManager.profile), look)


func _on_user_stats_received(_game_id: int = 0, result: int = 0, user_id: int = 0) -> void:
	if not user_id in _beat_pending:
		return
	_beat_pending.erase(user_id)
	if result != 1:  # k_EResultOK; a failed fetch just doesn't spread it this time
		return
	var got: Dictionary = steam.call("getUserAchievement", user_id, String(Achievements.BEAT_THE_DEV))
	if bool(got.get("achieved", false)):
		_beat_pending.clear()
		unlock_achievements([Achievements.BEAT_THE_DEV])


func _on_profile_changed() -> void:
	unlock_achievements(Achievements.from_profile(ProfileManager.profile))
	# A new outfit or colour (or the Steam inventory arriving) goes to the leaderboards a few
	# seconds later, so the boards show what this player wears now (Patrick 2026-11-17: "save that
	# data of the player and display correctly"); `submit_profile_bests` skips an unchanged look.
	_look_wait = LOOK_DELAY


# --- Gold Coins and premium pieces (Steam Inventory Service) -------------------------------------
# Gold Coins are bought for real money only (Patrick 2026-11-15): a gold pack (`CoinPack`) is a
# Steam bundle granting `CoinPack.GOLD_ITEM` items, which stay in the Steam inventory. Premium
# pieces and sets are item definitions (`CosmeticDef.steam_item`, `CosmeticPack.steam_item`) with
# an exchange recipe in Gold Coins (tools/steam/itemdefs.json is what Steamworks holds), so Steam
# keeps the balance and what was bought. On start, after each purchase and exchange the inventory is
# read: the pieces go to `ProfileManager.set_steam_owned`, the Gold Coins to `gold`. Handlers take optional arguments so a GodotSteam
# version with a slightly different signal never breaks the connection.

func _start_store() -> void:
	for sig: StringName in [&"inventory_result_ready", &"inventory_full_update", &"inventory_request_prices_result", &"inventory_start_purchase_result", &"overlay_toggled"]:
		if not steam.has_signal(sig):
			Log.warn(&"steam", "GodotSteam has no %s: real-money store off" % sig)
			return
	steam.connect(&"inventory_result_ready", _on_inventory_result)
	steam.connect(&"inventory_full_update", _on_inventory_full)
	steam.connect(&"inventory_request_prices_result", _on_prices)
	steam.connect(&"inventory_start_purchase_result", _on_purchase_result)
	steam.connect(&"overlay_toggled", _on_overlay_toggled)
	if steam.has_signal(&"inventory_definition_update"):
		steam.connect(&"inventory_definition_update", func(_defs: Variant = null) -> void: store_changed.emit())
	steam.call("loadItemDefinitions")
	steam.call("requestPrices")
	refresh_inventory()


## Whether real-money purchases can happen now (Steam running, prices known).
func store_ready() -> bool:
	return _available and currency != ""


## Asks Steam for the player's inventory again (the answer arrives later).
func refresh_inventory() -> void:
	if _available:
		steam.call("getAllItems")


## The price of item definition `def` in the player's currency ("" when unknown).
func price_text(def: int) -> String:
	if not prices.has(def) or currency == "":
		return ""
	return format_price(prices[def], currency)


## Opens the Steam overlay to pay for item definition `def` (a gold pack). False when the store is
## not ready or a purchase is already open.
func buy_item(def: int) -> bool:
	if not _available or buying or def <= 0:
		return false
	buying = true
	var items := PackedInt64Array([def])
	var qty := PackedInt32Array([1])
	steam.call("startPurchase", items, qty)
	return true


## An amount in the smallest unit of `code` as players read it: "0,99 €", "$0.99", "0.99 GBP".
static func format_price(amount: int, code: String) -> String:
	var whole: String = "%d.%02d" % [amount / 100, amount % 100]
	match code:
		"EUR":
			return "%s €" % whole.replace(".", ",")
		"USD":
			return "$%s" % whole
		"GBP":
			return "£%s" % whole
		_:
			return "%s %s" % [whole, code]


## The shop ids a Steam inventory listing grants (`getResultItems`: dictionaries with
## `item_definition`); a pack item stands for all its pieces.
static func owned_from_items(items: Array, shop: CosmeticShop) -> Array[StringName]:
	var out: Array[StringName] = []
	for it: Variant in items:
		if not it is Dictionary:
			continue
		var found: Resource = shop.by_steam_item(int((it as Dictionary).get("item_definition", 0)))
		var ids: Array[StringName] = []
		if found is CosmeticDef:
			ids.append((found as CosmeticDef).id)
		elif found is CosmeticPack:
			ids.append_array((found as CosmeticPack).pieces)
		for id: StringName in ids:
			if not id in out:
				out.append(id)
	return out


## The Gold Coin stacks in an inventory listing: [{item_id, quantity}].
static func gold_stacks(items: Array) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for it: Variant in items:
		if not it is Dictionary:
			continue
		var row: Dictionary = it
		var qty: int = int(row.get("quantity", 1))
		if int(row.get("item_definition", 0)) == CoinPack.GOLD_ITEM and qty > 0:
			out.append({"item_id": int(row.get("item_id", 0)), "quantity": qty})
	return out


## Which stacks pay `cost` Gold Coins: [item ids, quantities], empty when they don't reach.
static func gold_inputs(stacks: Array[Dictionary], cost: int) -> Array:
	var ids := PackedInt64Array()
	var qty := PackedInt32Array()
	var left: int = cost
	for st: Dictionary in stacks:
		if left <= 0:
			break
		var take: int = mini(int(st["quantity"]), left)
		ids.append(int(st["item_id"]))
		qty.append(take)
		left -= take
	return [] if left > 0 or cost <= 0 else [ids, qty]


## Buys item definition `def` (a premium piece or a set) for `cost` Gold Coins: Steam exchanges
## the coins for it (the recipe in its item definition). False when Steam isn't running, the Gold
## doesn't reach or an exchange is already on its way; the answer comes as `gold_spent`.
func buy_with_gold(def: int, cost: int) -> bool:
	if not _available or def <= 0 or not _exchanging.is_empty():
		return false
	var inputs: Array = gold_inputs(_gold_stacks, cost)
	if inputs.is_empty():
		return false
	var handle: int = int(steam.call("exchangeItems", PackedInt64Array([def]), PackedInt32Array([1]), inputs[0], inputs[1]))
	if handle <= 0:
		return false
	_exchanging[handle] = def
	return true


func _on_inventory_result(result: int = 0, handle: int = 0, _a: Variant = null, _b: Variant = null) -> void:
	if handle != 0 and handle == _dropping:
		_on_daily_drop(result, handle)
		return
	if _redeeming.has(handle):
		_on_redeemed(result, handle)
		return
	if _exchanging.has(handle):
		_exchanging.erase(handle)
		steam.call("destroyResult", handle)
		if result != 1:
			Log.warn(&"steam", "gold exchange failed (result %d)" % result)
		gold_spent.emit(result == 1)
		refresh_inventory()
		return
	_read_inventory(result, handle)


func _on_inventory_full(handle: int = 0, _a: Variant = null, _b: Variant = null) -> void:
	_read_inventory(1, handle)


func _read_inventory(result: int, handle: int) -> void:
	if result != 1:  # k_EResultOK
		Log.warn(&"steam", "inventory read failed (result %d)" % result)
		return
	var items: Variant = steam.call("getResultItems", handle)
	steam.call("destroyResult", handle)
	if not items is Array:
		return
	_gold_stacks = gold_stacks(items as Array)
	gold = 0
	for st: Dictionary in _gold_stacks:
		gold += int(st["quantity"])
	var ids: Array[StringName] = owned_from_items(items as Array, CosmeticShop.default())
	Log.info(&"steam", "inventory: %d pieces, %d Gold Coins" % [ids.size(), gold])
	ProfileManager.set_steam_owned(ids)
	store_changed.emit()
	_redeem(items as Array)


# --- Daily Spin (`DailyWheel`) -------------------------------------------------------------------
# Steam decides the spin: `triggerItemDrop` on the wheel's playtime generator grants at most one
# prize per cooldown per account, picked by the generator's weights. The prize is a token in the
# Steam inventory; `_redeem` pays it out (Coins and mystery pieces into the profile after Steam has
# consumed the token, Gold by an exchange for a Gold Coin bundle). Tokens left over (the game shut
# while redeeming) are paid on the next inventory read.

## Whether Steam can spin the wheel: Steam is running and the wheel's item definitions are loaded
## (until they are uploaded to Steamworks the game spins locally, without Gold or the skin).
func daily_ready() -> bool:
	return _available and def_known(DailyWheel.GENERATOR)


## Whether Steam knows item definition `def` (loaded from Steamworks).
func def_known(def: int) -> bool:
	if not _available:
		return false
	return prop_text(steam.call("getItemDefinitionProperty", def, "name")) != ""


## The text of a `getItemDefinitionProperty` answer (a String, or a Dictionary in some GodotSteam
## versions).
static func prop_text(v: Variant) -> String:
	if v is Dictionary:
		for key: String in ["value", "property", "properties", "name"]:
			if (v as Dictionary).has(key):
				return str((v as Dictionary)[key]).strip_edges()
		return ""
	return str(v).strip_edges() if v != null else ""


## Unix seconds: Steam's server time when Steam runs (turning the PC clock doesn't move it), else
## the PC's clock.
func now() -> int:
	if _available:
		var t: int = int(steam.call("getServerRealTime"))
		if t > 0:
			return t
	return int(Time.get_unix_time_from_system())


## Spins the wheel on Steam (the answer comes as `daily_spun`). False when Steam can't spin now.
func daily_spin() -> bool:
	if not daily_ready() or _dropping != 0:
		return false
	var h: int = int(steam.call("triggerItemDrop", DailyWheel.GENERATOR))
	if h <= 0:
		return false
	_dropping = h
	return true


func _on_daily_drop(result: int, handle: int) -> void:
	_dropping = 0
	var items: Variant = steam.call("getResultItems", handle) if result == 1 else []
	steam.call("destroyResult", handle)
	var index: int = -1
	if items is Array:
		for it: Variant in items:
			if it is Dictionary:
				var i: int = DailyWheel.index_of_item(int((it as Dictionary).get("item_definition", 0)))
				if i >= 0:
					index = i
					break
	if result != 1:
		Log.warn(&"steam", "daily spin failed (result %d)" % result)
	Log.info(&"steam", "daily spin: %s" % ("nothing yet" if index < 0 else DailyWheel.label(index)))
	daily_spun.emit({"ok": index >= 0, "index": index})
	if index >= 0:
		refresh_inventory()  # the token (or the skin) arrives with it; `_redeem` pays it out


## Pays out the wheel tokens in an inventory listing (each once at a time).
func _redeem(items: Array) -> void:
	for it: Variant in items:
		if not it is Dictionary:
			continue
		var row: Dictionary = it
		var def: int = int(row.get("item_definition", 0))
		var item_id: int = int(row.get("item_id", 0))
		var qty: int = int(row.get("quantity", 1))
		var i: int = DailyWheel.index_of_item(def)
		if i < 0 or qty <= 0 or item_id == 0 or item_id in _redeem_items:
			continue
		var kind: StringName = DailyWheel.segment(i)["kind"]
		var h: int = 0
		if kind == DailyWheel.KIND_COINS or kind == DailyWheel.KIND_PIECE:
			h = int(steam.call("consumeItem", item_id, qty))
		elif kind == DailyWheel.KIND_GOLD:
			qty = 1  # one bundle per token; more tokens in the stack follow on the next read
			h = int(steam.call("exchangeItems", PackedInt64Array([DailyWheel.gold_bundle(def)]), PackedInt32Array([1]), PackedInt64Array([item_id]), PackedInt32Array([1])))
		if h > 0:
			_redeeming[h] = {"item_id": item_id, "def": def, "quantity": qty}
			_redeem_items.append(item_id)


func _on_redeemed(result: int, handle: int) -> void:
	var r: Dictionary = _redeeming[handle]
	_redeeming.erase(handle)
	_redeem_items.erase(int(r["item_id"]))
	steam.call("destroyResult", handle)
	if result != 1:
		Log.warn(&"steam", "daily spin prize not paid (result %d), trying again later" % result)
		return
	var i: int = DailyWheel.index_of_item(int(r["def"]))
	var seg: Dictionary = DailyWheel.segment(i)
	var prize: Dictionary = {"index": i, "coins": 0, "piece": &"", "gold": 0}
	if seg["kind"] == DailyWheel.KIND_GOLD:
		prize["gold"] = int(seg["amount"]) * int(r["quantity"])
		refresh_inventory()
	else:
		for n: int in int(r["quantity"]):
			var got: Dictionary = ProfileManager.add_wheel_prize(seg["kind"], int(seg["amount"]))
			prize["coins"] = int(prize["coins"]) + int(got["coins"])
			if got["piece"] != &"":
				prize["piece"] = got["piece"]
	Log.info(&"steam", "daily spin prize paid: %s" % DailyWheel.label(i))
	daily_redeemed.emit(prize)


func _on_prices(result: int = 0, code: Variant = "", _a: Variant = null) -> void:
	if result != 1:
		Log.warn(&"steam", "store prices unavailable (result %d)" % result)
		return
	currency = str(code)
	prices.clear()
	var shop: CosmeticShop = CosmeticShop.default()
	var defs: Array[int] = []
	for c: CoinPack in shop.coin_packs:
		defs.append(c.steam_item)
	for def: int in defs:
		var p: Variant = steam.call("getItemPrice", def)
		if p is Dictionary and int((p as Dictionary).get("price", 0)) > 0:
			prices[def] = int((p as Dictionary).get("price", 0))
	Log.info(&"steam", "store prices: %d items in %s" % [prices.size(), currency])
	store_changed.emit()


func _on_purchase_result(result: Variant = null, _order: Variant = null, _transaction: Variant = null, _a: Variant = null) -> void:
	var ok: bool = str(result) in ["success", "1", "true"]
	if not ok:
		# StartPurchase itself failed, so the overlay never opened (unreleased app, item not for sale here, old item list).
		push_warning("Steam StartPurchase failed: %s" % str(result))
		buying = false
		purchase_finished.emit(false)
	# Paid: Steam grants the items, the inventory update follows (also re-read when the overlay closes).
	refresh_inventory()


func _on_overlay_toggled(active: Variant = false, _user: Variant = null, _app: Variant = null) -> void:
	if bool(active) or not buying:
		return
	buying = false
	refresh_inventory()
	purchase_finished.emit(true)


func _skip_reason() -> String:
	var user_args: PackedStringArray = OS.get_cmdline_user_args()
	if "--no-steam" in user_args:
		return "--no-steam"
	if "--server" in user_args:
		return "dedicated server"
	if DisplayServer.get_name() == "headless":
		return "headless"
	if not Engine.has_singleton("Steam"):
		return "GodotSteam extension not loaded"
	return ""


## `+connect_lobby <id>` from the engine's command line (0 if absent).
static func _launch_lobby(args: PackedStringArray) -> int:
	var i: int = args.find("+connect_lobby")
	if i >= 0 and i + 1 < args.size() and args[i + 1].is_valid_int():
		return int(args[i + 1])
	return 0


## Opens Steam's floating on-screen keyboard over a text field (`rect` in window pixels) so a
## gamepad or the Deck can type into it; the keys arrive as normal key presses. False when Steam
## can't show one here (no Steam, not in Big Picture or on a Deck): use `PadKeyboard` instead.
func show_text_keyboard(rect: Rect2, single_line: bool = true) -> bool:
	if not _available or not steam.has_method(&"showFloatingGamepadTextInput"):
		return false
	var mode: int = 0 if single_line else 1  # FLOATING_GAMEPAD_TEXT_INPUT_MODE_SINGLE_LINE / MULTIPLE_LINES
	return bool(steam.call("showFloatingGamepadTextInput", mode, int(rect.position.x), int(rect.position.y), int(rect.size.x), int(rect.size.y)))


## Closes Steam's floating keyboard (after the text was sent).
func hide_text_keyboard() -> void:
	if _available and steam.has_method(&"dismissFloatingGamepadTextInput"):
		steam.call("dismissFloatingGamepadTextInput")


## True when a Steam client is running and the API initialised.
func is_available() -> bool:
	return _available


## For `VersionCheck`: {from_steam (this copy runs from the Steam install), installed (its Steam
## build id), branches (GodotSteam `getBetaInfo()`: each branch's live build)}; {} without Steam.
func steam_builds() -> Dictionary:
	if not _available:
		return {}
	var out: Dictionary = {"installed": int(steam.call("getAppBuildId")), "branches": []}
	var dir: Variant = steam.call("getAppInstallDir", APP_ID) if steam.has_method("getAppInstallDir") else ""
	var install: String = str((dir as Dictionary).get("directory", "")) if typeof(dir) == TYPE_DICTIONARY else str(dir)
	out["from_steam"] = runs_from(OS.get_executable_path(), install)
	if _no_arg_method("getBetaInfo"):
		var branches: Variant = steam.call("getBetaInfo")
		if typeof(branches) == TYPE_ARRAY:
			out["branches"] = branches
	return out


## Whether the executable at `exe` lives inside the Steam install folder `install`.
static func runs_from(exe: String, install: String) -> bool:
	if install.strip_edges() == "" or exe == "":
		return false
	var e: String = exe.replace("\\", "/").simplify_path().to_lower()
	var d: String = install.replace("\\", "/").simplify_path().to_lower().trim_suffix("/") + "/"
	return e.begins_with(d)


func _no_arg_method(method: String) -> bool:
	if not steam.has_method(method):
		return false
	for m: Dictionary in steam.get_method_list():
		if str(m.get("name", "")) == method:
			return (m.get("args", []) as Array).size() == (m.get("default_args", []) as Array).size()
	return false


## Steam persona name, or the OS user name as a stand-in.
func get_persona_name() -> String:
	if _available and _persona != "":
		return _persona
	var user: String = OS.get_environment("USER")
	if user.is_empty():
		user = OS.get_environment("USERNAME")
	return user if not user.is_empty() else "Player"


## Our Steam ID (0 without Steam).
func get_steam_id() -> int:
	return _steam_id


## Creates our party lobby, public (BROWSE LOBBIES lists it) or private (friends and invites
## only); `lobby_ready` follows. Returns false without Steam.
func create_lobby(party_name: String, max_members: int, public: bool = false) -> bool:
	if not _available:
		last_error = "Steam is not running."
		return false
	leave_lobby()
	lobby_owner = true
	steam.call("createLobby", LOBBY_TYPE_PUBLIC if public else LOBBY_TYPE_FRIENDS_ONLY, max_members)
	set_meta(&"party_name", party_name)
	set_meta(&"party_public", public)
	return true


## Asks Steam for the public lobbies of this game, worldwide, with a free seat;
## `public_lobbies_received` follows. Every version is asked for (Patrick 2026-11-16: "Public
## lobbies are not found of other ppl"): Steam updates players at different times, and a lobby of
## another version used to vanish without a word; BROWSE LOBBIES now shows it with the version
## needed instead. Returns false without Steam or while a request is running.
func request_public_lobbies() -> bool:
	if not _available:
		return false
	var now: int = Time.get_ticks_msec()
	if browsing and now - _browse_started < BROWSE_TIMEOUT_MS:
		return false  # Steam has not answered the last one yet
	browsing = true
	_browse_started = now
	steam.call("addRequestLobbyListStringFilter", "game", LOBBY_GAME, LOBBY_COMPARISON_EQUAL)
	steam.call("addRequestLobbyListStringFilter", "public", "1", LOBBY_COMPARISON_EQUAL)
	steam.call("addRequestLobbyListFilterSlotsAvailable", 1)
	steam.call("addRequestLobbyListDistanceFilter", LOBBY_DISTANCE_FILTER_WORLDWIDE)
	steam.call("addRequestLobbyListResultCountFilter", PUBLIC_LOBBY_LIMIT)
	steam.call("requestLobbyList")
	return true


## Joins a friend's lobby; `lobby_entered` follows.
func join_lobby(id: int) -> bool:
	if not _available or id == 0:
		last_error = "Steam is not running."
		return false
	leave_lobby()
	lobby_owner = false
	steam.call("joinLobby", id)
	return true


func leave_lobby() -> void:
	if _available and lobby_id != 0:
		steam.call("leaveLobby", lobby_id)
		steam.call("clearRichPresence")
	lobby_id = 0
	lobby_owner = false
	_info_sent = ""


## Opens the Steam overlay's invite dialog for our lobby.
func invite_friends() -> bool:
	if not _available or lobby_id == 0:
		return false
	steam.call("activateGameOverlayInviteDialog", lobby_id)
	return true


## The host's game: what BROWSE LOBBIES shows about our lobby (settings and the beans in it, see
## `LobbyInfo`). Only an owned lobby is written, and only when something changed.
func publish_lobby_info(info: Dictionary) -> bool:
	if not _available or not lobby_owner or lobby_id == 0:
		return false
	var text: String = LobbyInfo.to_text(info)
	if text == _info_sent:
		return false
	_info_sent = text
	steam.call("setLobbyData", lobby_id, LobbyInfo.KEY, text)
	return true


## Lobby data of any lobby we know ("" if unknown).
func lobby_data(id: int, key: String) -> String:
	return str(steam.call("getLobbyData", id, key)) if _available else ""


## The lobby's owner (the host's Steam ID).
func lobby_owner_of(id: int) -> int:
	return int(steam.call("getLobbyOwner", id)) if _available else 0


func member_count() -> int:
	return int(steam.call("getNumLobbyMembers", lobby_id)) if _available and lobby_id != 0 else 0


## Lobbies of friends playing this game, ONE entry per lobby however many friends are in it
## (Patrick: "If i have 4 friends in the lobby, it shows 4 times the same lobby"):
## [{lobby, party, build, friends: [names], members, max}]. Our own lobby is left out, and so
## are other games' lobbies once Steam has their data.
func friend_lobbies() -> Array[Dictionary]:
	var seen: Array[Dictionary] = []
	if not _available:
		return group_friend_lobbies(seen)
	var n: int = int(steam.call("getFriendCount", FRIEND_FLAG_IMMEDIATE))
	for i: int in n:
		var fid: int = int(steam.call("getFriendByIndex", i, FRIEND_FLAG_IMMEDIATE))
		var game: Dictionary = steam.call("getFriendGamePlayed", fid)
		if int(game.get("id", 0)) != APP_ID or int(game.get("lobby", 0)) == 0:
			continue
		var lid: int = int(game["lobby"])
		if lid == lobby_id:
			continue
		var kind: String = lobby_data(lid, "game")
		if kind == "":
			steam.call("requestLobbyData", lid)  # arrives later; the list refreshes
		elif kind != LOBBY_GAME:
			continue
		seen.append({"name": str(steam.call("getFriendPersonaName", fid)), "lobby": lid, "party": lobby_data(lid, "name"),
			"build": lobby_data(lid, "build"), "public": lobby_data(lid, "public") == "1", "members": int(steam.call("getNumLobbyMembers", lid)), "max": int(steam.call("getLobbyMemberLimit", lid)),
			"info": LobbyInfo.parse(lobby_data(lid, LobbyInfo.KEY))})
	return group_friend_lobbies(seen)


## One entry per lobby id, in first-seen order, with every friend's name in `friends`.
static func group_friend_lobbies(seen: Array[Dictionary]) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var at: Dictionary[int, int] = {}
	for f: Dictionary in seen:
		var lid: int = int(f["lobby"])
		if at.has(lid):
			var e: Dictionary = out[at[lid]]
			(e["friends"] as Array).append(str(f["name"]))
			e["members"] = maxi(int(e["members"]), int(f.get("members", 0)))
			continue
		at[lid] = out.size()
		out.append({"lobby": lid, "party": str(f.get("party", "")), "build": str(f.get("build", "")), "public": bool(f.get("public", false)), "friends": [str(f["name"])],
			"members": int(f.get("members", 0)), "max": int(f.get("max", 0)), "info": f.get("info", {})})
	for e: Dictionary in out:
		e["members"] = maxi(int(e["members"]), (e["friends"] as Array).size())  # Steam may not know yet
	return out


## "Anna", "Anna and Ben", "Anna, Ben and 2 more".
static func friends_text(names: Array) -> String:
	match names.size():
		0:
			return ""
		1:
			return str(names[0])
		2:
			return "%s and %s" % [names[0], names[1]]
	return "%s, %s and %d more" % [names[0], names[1], names.size() - 2]


# --- callbacks ---------------------------------------------------------------------------------

func _on_lobby_created(result: int, id: int) -> void:
	if result != 1 or id == 0:
		last_error = "Steam could not create the lobby (error %d)." % result
		Log.warn(&"steam", last_error)
		lobby_owner = false
		lobby_ready.emit(0)
		return
	lobby_id = id
	var party: String = str(get_meta(&"party_name", "%s's lobby" % get_persona_name()))
	steam.call("setLobbyData", id, "game", LOBBY_GAME)
	steam.call("setLobbyData", id, "build", Protocol.BUILD_ID)
	steam.call("setLobbyData", id, "name", party)
	steam.call("setLobbyData", id, "public", "1" if bool(get_meta(&"party_public", false)) else "0")
	steam.call("setLobbyJoinable", id, true)
	steam.call("setRichPresence", "status", party)
	Log.info(&"steam", "party lobby %d created" % id)
	lobby_ready.emit(id)


func _on_lobby_joined(id: int, _permissions: int, _locked: bool, response: int) -> void:
	if lobby_owner:
		return  # our own lobby: `lobby_created` handled it
	if response != CHAT_ROOM_ENTER_RESPONSE_SUCCESS:
		last_error = "Could not join the lobby (Steam says %s)." % _enter_text(response)
		lobby_entered.emit({"lobby_id": id, "ok": false, "error": last_error})
		return
	lobby_id = id
	var owner: int = lobby_owner_of(id)
	lobby_entered.emit({"lobby_id": id, "ok": true, "owner": owner, "game": lobby_data(id, "game"), "build": lobby_data(id, "build"), "name": lobby_data(id, "name")})


func _on_lobby_match_list(lobbies: Array = []) -> void:
	browsing = false
	var out: Array[Dictionary] = []
	for v: Variant in lobbies:
		var lid: int = int(v)
		if lid == 0 or lid == lobby_id:
			continue
		var e: Dictionary = public_lobby_entry(lid, lobby_data(lid, "name"), int(steam.call("getNumLobbyMembers", lid)), int(steam.call("getLobbyMemberLimit", lid)),
			LobbyInfo.parse(lobby_data(lid, LobbyInfo.KEY)), lobby_data(lid, "build"))
		out.append(e)
	Log.info(&"steam", "public lobby search: %d found (%d other versions)" % [out.size(), out.filter(func(e: Dictionary) -> bool: return str(e["build"]) != Protocol.BUILD_ID).size()])
	public_lobbies_received.emit(merge_friend_public(out, friend_lobbies()))


## One row of BROWSE LOBBIES (`info`: the host's `LobbyInfo`, {} from an older host; `build`: the
## host's version, "" when Steam has not sent it yet).
static func public_lobby_entry(lid: int, party: String, members: int, max_members: int, info: Dictionary = {}, build: String = Protocol.BUILD_ID) -> Dictionary:
	return {"lobby": lid, "name": party if party.strip_edges() != "" else "Lobby", "members": members, "max": max_members if max_members > 0 else Protocol.MAX_PLAYERS, "info": info, "build": build}


## Public lobbies of friends the search missed are added too (a friend's public lobby must always
## be in BROWSE LOBBIES, whatever Steam's search returns), each lobby once.
static func merge_friend_public(found: Array[Dictionary], friends: Array[Dictionary]) -> Array[Dictionary]:
	var out: Array[Dictionary] = found.duplicate()
	var ids: Dictionary[int, bool] = {}
	for e: Dictionary in found:
		ids[int(e["lobby"])] = true
	for f: Dictionary in friends:
		var lid: int = int(f["lobby"])
		if ids.has(lid) or not bool(f.get("public", false)):
			continue
		if int(f.get("max", 0)) > 0 and int(f.get("members", 0)) >= int(f["max"]):
			continue  # full: Steam's search leaves those out as well
		ids[lid] = true
		out.append(public_lobby_entry(lid, str(f.get("party", "")), int(f.get("members", 0)), int(f.get("max", 0)), f.get("info", {}), str(f.get("build", ""))))
	return out


func _on_lobby_chat_update(id: int, _changed: int, _making_change: int, _state: int) -> void:
	if id == lobby_id:
		lobby_members_changed.emit(id)


func _on_join_requested(id: int, _friend: int) -> void:
	Log.info(&"steam", "join requested: lobby %d" % id)
	pending_lobby = id
	join_requested.emit(id)


static func _enter_text(response: int) -> String:
	match response:
		2:
			return "the lobby no longer exists"
		3:
			return "you are not allowed in"
		4:
			return "the lobby is full"
		6:
			return "you are banned"
	return "error %d" % response
