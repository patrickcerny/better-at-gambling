class_name NetTransport
extends RefCounted
## Transport-agnostic packet pipe (§4.1 `TransportFactory`): the NetSession only sees peers,
## channels and byte packets. Implementations: `ENetTransport` (online), `DelayedTransport`
## (latency/loss wrapper for tests). Peer 1 is always the server.

signal peer_connected(peer: int)
signal peer_disconnected(peer: int)
## Client only: the connection attempt failed.
signal connection_failed

const SERVER_PEER: int = 1

## Payload bytes sent/received, total and per peer (before ENet compression: an upper bound).
var bytes_out: int = 0
var bytes_in: int = 0
var bytes_out_by_peer: Dictionary[int, int] = {}


## Pumps the connection. Returns received packets: [{peer, channel, data: PackedByteArray}].
func poll() -> Array[Dictionary]:
	return []


## Sends to one peer (`0` = every connected peer).
func send(_peer: int, _channel: int, _reliable: bool, _data: PackedByteArray) -> void:
	pass


## Disconnects one peer (server) after flushing what was queued.
func kick(_peer: int) -> void:
	pass


## Closes the connection/host.
func close() -> void:
	pass


## True once the client is connected / the server is listening.
func is_active() -> bool:
	return false


## Unique id of this end (1 on the server).
func local_id() -> int:
	return 0


func _count_out(peer: int, n: int) -> void:
	bytes_out += n
	bytes_out_by_peer[peer] = bytes_out_by_peer.get(peer, 0) + n
