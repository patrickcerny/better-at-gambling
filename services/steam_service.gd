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

## The game's own Steamworks App ID (was 480 "Spacewar" for tests until 0.9.16).
const APP_ID: int = 5623410
const LOBBY_GAME: String = "better_at_gambling"
const LOBBY_TYPE_FRIENDS_ONLY: int = 1
const CHAT_ROOM_ENTER_RESPONSE_SUCCESS: int = 1
const FRIEND_FLAG_IMMEDIATE: int = 4

## The GodotSteam singleton (null when the extension is missing).
var steam: Object = null
## Lobby we are in (0 = none) and whether we own it.
var lobby_id: int = 0
var lobby_owner: bool = false
## A lobby to join that arrived before anyone could act on it (launch argument, or a join request
## while a match was loading). The main menu picks it up.
var pending_lobby: int = 0
var last_error: String = ""

var _available: bool = false
var _steam_id: int = 0
var _persona: String = ""
## Achievements already handed to Steam this run (asked once each).
var _unlocked: Array[StringName] = []
## Real-money store (Steam Inventory Service): the player's currency ("" until Steam answers) and
## each item definition's price in that currency's smallest unit.
var currency: String = ""
var prices: Dictionary[int, int] = {}
## A purchase is waiting for the overlay.
var buying: bool = false


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
	Log.info(&"steam", "Steam on: %s (app %d)" % [_persona, APP_ID])
	_start_store()
	# Lifetime achievements follow the profile (level-ups, matches, the shop) and catch up on start.
	ProfileManager.changed.connect(_on_profile_changed)
	_on_profile_changed()


func _process(_delta: float) -> void:
	if _available:
		steam.call("run_callbacks")


func _exit_tree() -> void:
	if _available:
		leave_lobby()
		steam.call("steamShutdown")
		_available = false


## Unlocks Steam achievements by API name (`Achievements.DEFS`) and stores them once. Without
## Steam nothing happens. Returns the ones newly unlocked this call.
func unlock_achievements(ids: Array[StringName]) -> Array[StringName]:
	var fresh: Array[StringName] = []
	if not _available or ids.is_empty():
		return fresh
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
	return fresh


func _on_profile_changed() -> void:
	unlock_achievements(Achievements.from_profile(ProfileManager.profile))


# --- Real-money store (Steam Inventory Service) -------------------------------------------------
# Every paid outfit piece and every pack is a Steam item definition (`CosmeticDef.steam_item`,
# `CosmeticPack.steam_item`; tools/steam/itemdefs.json is what Steamworks holds). Steam charges,
# converts the price and keeps the record: on start and after each purchase the inventory is read
# and handed to `ProfileManager.set_steam_owned`. Handlers take optional arguments so a GodotSteam
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


## Opens the Steam overlay to pay for item definition `def` (a piece or a pack). False when the
## store is not ready or a purchase is already open.
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


func _on_inventory_result(result: int = 0, handle: int = 0, _a: Variant = null, _b: Variant = null) -> void:
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
	var ids: Array[StringName] = owned_from_items(items as Array, CosmeticShop.default())
	Log.info(&"steam", "inventory: %d pieces" % ids.size())
	ProfileManager.set_steam_owned(ids)
	store_changed.emit()


func _on_prices(result: int = 0, code: Variant = "", _a: Variant = null) -> void:
	if result != 1:
		Log.warn(&"steam", "store prices unavailable (result %d)" % result)
		return
	currency = str(code)
	prices.clear()
	var shop: CosmeticShop = CosmeticShop.default()
	var defs: Array[int] = []
	for d: CosmeticDef in shop.items:
		if d.steam_item > 0:
			defs.append(d.steam_item)
	for k: CosmeticPack in shop.packs:
		defs.append(k.steam_item)
	for def: int in defs:
		var p: Variant = steam.call("getItemPrice", def)
		if p is Dictionary and int((p as Dictionary).get("price", 0)) > 0:
			prices[def] = int((p as Dictionary).get("price", 0))
	Log.info(&"steam", "store prices: %d items in %s" % [prices.size(), currency])
	store_changed.emit()


func _on_purchase_result(result: Variant = null, _order: Variant = null, _transaction: Variant = null, _a: Variant = null) -> void:
	var ok: bool = str(result) in ["success", "1", "true"]
	if not ok:
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


## True when a Steam client is running and the API initialised.
func is_available() -> bool:
	return _available


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


## Creates our friends-only party lobby; `lobby_ready` follows. Returns false without Steam.
func create_lobby(party_name: String, max_members: int) -> bool:
	if not _available:
		last_error = "Start Steam to host."
		return false
	leave_lobby()
	lobby_owner = true
	steam.call("createLobby", LOBBY_TYPE_FRIENDS_ONLY, max_members)
	set_meta(&"party_name", party_name)
	return true


## Joins a friend's lobby; `lobby_entered` follows.
func join_lobby(id: int) -> bool:
	if not _available or id == 0:
		last_error = "Start Steam to join friends."
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


## Opens the Steam overlay's invite dialog for our lobby.
func invite_friends() -> bool:
	if not _available or lobby_id == 0:
		return false
	steam.call("activateGameOverlayInviteDialog", lobby_id)
	return true


## Lobby data of any lobby we know ("" if unknown).
func lobby_data(id: int, key: String) -> String:
	return str(steam.call("getLobbyData", id, key)) if _available else ""


## The lobby's owner (the host's Steam ID).
func lobby_owner_of(id: int) -> int:
	return int(steam.call("getLobbyOwner", id)) if _available else 0


func member_count() -> int:
	return int(steam.call("getNumLobbyMembers", lobby_id)) if _available and lobby_id != 0 else 0


## Friends playing this App ID inside a lobby: [{steam_id, name, lobby, party}] ("party" is the
## lobby's name once Steam has its data; lobbies of other "Spacewar" games are left out once known).
func friend_lobbies() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if not _available:
		return out
	var n: int = int(steam.call("getFriendCount", FRIEND_FLAG_IMMEDIATE))
	for i: int in n:
		var fid: int = int(steam.call("getFriendByIndex", i, FRIEND_FLAG_IMMEDIATE))
		var game: Dictionary = steam.call("getFriendGamePlayed", fid)
		if int(game.get("id", 0)) != APP_ID or int(game.get("lobby", 0)) == 0:
			continue
		var lid: int = int(game["lobby"])
		var kind: String = lobby_data(lid, "game")
		if kind == "":
			steam.call("requestLobbyData", lid)  # arrives later; the list refreshes
		elif kind != LOBBY_GAME:
			continue
		out.append({"steam_id": fid, "name": str(steam.call("getFriendPersonaName", fid)), "lobby": lid, "party": lobby_data(lid, "name"), "build": lobby_data(lid, "build")})
	return out


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
