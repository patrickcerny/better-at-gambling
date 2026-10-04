class_name MoneyLedger
extends RefCounted
## Append-only record of every money change, for audits, stats and conservation tests.

## Entries: {seq, player, amount, reason, source, balance}.
var entries: Array[Dictionary] = []


## Appends one entry.
func record(player: int, amount: int, reason: StringName, source: StringName, balance_after: int) -> void:
	entries.append({"seq": entries.size(), "player": player, "amount": amount, "reason": reason, "source": source, "balance": balance_after})


## Sum of all recorded amounts, optionally for one player (-1 = all).
func total(player: int = -1) -> int:
	var sum: int = 0
	for e: Dictionary in entries:
		if player < 0 or int(e["player"]) == player:
			sum += int(e["amount"])
	return sum


## Sum of amounts per reason.
func by_reason() -> Dictionary[StringName, int]:
	var out: Dictionary[StringName, int] = {}
	for e: Dictionary in entries:
		var r: StringName = e["reason"]
		out[r] = out.get(r, 0) + int(e["amount"])
	return out
