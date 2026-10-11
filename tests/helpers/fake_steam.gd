class_name FakeSteam
extends RefCounted
## A stand-in for the GodotSteam `Steam` singleton's Networking Messages part, for tests that run
## without a Steam client. Users share a `Network`: a message to a user who never talked to the
## sender raises `network_messages_session_request` there and waits until that user accepts the
## session (as Steam does). Every send is recorded with its flags and channel.

signal network_messages_session_request(remote_steam_id: int)
signal network_messages_session_failed(reason: int, remote_steam_id: int, connection_state: int, debug_message: String)


## The shared "Steam backbone".
class Network:
	extends RefCounted
	var users: Dictionary[int, FakeSteam] = {}

	func user(steam_id: int) -> FakeSteam:
		var u := FakeSteam.new()
		u.steam_id = steam_id
		u.network = self
		users[steam_id] = u
		return u


var steam_id: int = 0
var network: Network
## [{to, data, flags, channel}]
var sent: Array[Dictionary] = []
var accepted: Dictionary[int, bool] = {}
var closed: Array[int] = []
var ping_ms: int = 42
## Unreliable messages are dropped while true.
var drop_unreliable: bool = false
## Steam channel → [{identity, payload, channel, flags}] ready to read.
var _inbox: Dictionary[int, Array] = {}
## Sender → messages waiting for the session to be accepted.
var _waiting: Dictionary[int, Array] = {}


func sendMessageToUser(remote_steam_id: int, data: PackedByteArray, flags: int, channel: int) -> int:
	sent.append({"to": remote_steam_id, "data": data, "flags": flags, "channel": channel})
	accepted[remote_steam_id] = true  # talking first opens the session on our side
	var target: FakeSteam = network.users.get(remote_steam_id)
	if target == null or (drop_unreliable and (flags & 8) == 0):
		return 1
	target._arrive(steam_id, data, flags, channel)
	return 1


func receiveMessagesOnChannel(channel: int, max_messages: int) -> Array:
	var q: Array = _inbox.get(channel, [])
	var out: Array = q.slice(0, max_messages)
	_inbox[channel] = q.slice(max_messages)
	return out


func acceptSessionWithUser(remote_steam_id: int) -> bool:
	accepted[remote_steam_id] = true
	for m: Dictionary in _waiting.get(remote_steam_id, []):
		_queue(m)
	_waiting.erase(remote_steam_id)
	return true


func closeSessionWithUser(remote_steam_id: int) -> bool:
	closed.append(remote_steam_id)
	accepted.erase(remote_steam_id)
	return true


func getSessionConnectionInfo(_remote_steam_id: int, _get_connection: bool, _get_status: bool) -> Dictionary:
	return {"connection_state": 3, "ping": ping_ms}


## Sends that went to `to` on game channels (not the transport's control channel).
func game_sends(to: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for s: Dictionary in sent:
		if int(s["to"]) == to and int(s["channel"]) != SteamTransport.CONTROL_CHANNEL:
			out.append(s)
	return out


func _arrive(from: int, data: PackedByteArray, flags: int, channel: int) -> void:
	var m: Dictionary = {"identity": from, "payload": data, "channel": channel, "flags": flags, "size": data.size()}
	if accepted.has(from):
		_queue(m)
		return
	var first: bool = not _waiting.has(from)
	if first:
		_waiting[from] = []
	_waiting[from].append(m)
	if first:
		network_messages_session_request.emit(from)


func _queue(m: Dictionary) -> void:
	var ch: int = int(m["channel"])
	if not _inbox.has(ch):
		_inbox[ch] = []
	_inbox[ch].append(m)
