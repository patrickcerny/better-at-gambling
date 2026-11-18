class_name InventoryProof
extends RefCounted
## Host mode: checks a friend's Steam-signed inventory (security audit 2026-11-18). Premium outfit
## pieces (Gold Coins, sets, the Daily Spin skin) live in the Steam inventory, but the room server
## used to take a joining player's outfit on trust, so a modified game could wear them for free.
## The joining game sends `SteamSvc.inventory_proof` (Steam's `SerializeResult`) in its hello; the
## host's `HostBridge` hands it to `start`, `poll`s until Steam has checked the signature, and
## stamps the pieces it really grants into the hello as `steam_owned`. The proof must belong to
## the friend's own Steam ID (`CheckResultSteamID`), so nobody can pass on someone else's.
##
## `steam` is the GodotSteam singleton, or a fake with the same methods in tests.

## EResult values `GetResultStatus` reports.
const RESULT_OK: int = 1
const RESULT_PENDING: int = 22
## The proof is older than an hour: Steam still vouches for the items (a soft failure).
const RESULT_EXPIRED: int = 27
## Larger proofs are refused unread (a full inventory serializes to a few kilobytes).
const MAX_BYTES: int = 256 * 1024

var steam: Object


func _init(p_steam: Object = null) -> void:
	steam = p_steam
	if steam == null and Engine.has_singleton("Steam"):
		steam = Engine.get_singleton("Steam")


## Starts checking `proof`. Returns the result handle, or 0 when there is nothing to check.
func start(proof: Variant) -> int:
	if steam == null or not proof is PackedByteArray:
		return 0
	var bytes: PackedByteArray = proof
	if bytes.is_empty() or bytes.size() > MAX_BYTES:
		return 0
	return maxi(int(steam.call("deserializeResult", bytes)), 0)


## null while Steam still checks `handle`; then the shop ids the proof really grants to
## `steam_id` (empty for a forged, foreign or broken proof). The handle is freed once answered.
func poll(steam_id: int, handle: int) -> Variant:
	var status: int = int(steam.call("getResultStatus", handle))
	if status == RESULT_PENDING:
		return null
	var owned: Array[StringName] = []
	if (status == RESULT_OK or status == RESULT_EXPIRED) and bool(steam.call("checkResultSteamID", steam_id, handle)):
		var items: Variant = steam.call("getResultItems", handle)
		if items is Array:
			owned = SteamSvc.owned_from_items(items as Array, CosmeticShop.default())
	release(handle)
	return owned


## Frees a handle nobody waits for any more.
func release(handle: int) -> void:
	if handle > 0 and steam != null:
		steam.call("destroyResult", handle)
