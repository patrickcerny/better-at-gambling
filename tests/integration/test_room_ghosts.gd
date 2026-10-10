extends GutTest
## Old fix batch: "ghost players keeping rooms open". A room counts only the peers that are really
## connected: one that drops while the orchestrator still checks its join token (or before the
## match scene attached the server) must never be admitted afterwards, or it sits in the room
## forever, no disconnect left to come, and the room never closes.


## The orchestrator: join tokens are answered when the test says so.
class SlowOrchestrator:
	extends HttpJson
	signal answer
	var verified: int = 0

	func post(url: String, _body: Dictionary) -> Dictionary:
		if url.ends_with("verify"):
			await answer
			verified += 1
			return {"status": 200, "body": {"player_uid": "uid-%d" % verified, "display_name": "Guest %d" % verified}}
		return {"status": 200, "body": {}}


## Records the close instead of quitting the test run.
class TestHost:
	extends RoomHost
	var closed_reason: String = ""

	func _close(reason: String) -> void:
		_closing = true
		closed_reason = reason


var fx: ServerFixture
var host: TestHost
var orch: SlowOrchestrator


func before_each() -> void:
	fx = ServerFixture.new(0)
	fx.server.room_mode = true
	fx.server.open_lobby()
	host = TestHost.new()
	add_child_autofree(host)
	host.orchestrator = "http://orchestrator.invalid"
	host.empty_timeout = 120.0
	orch = SlowOrchestrator.new()
	host.add_child(orch)
	host.http = orch
	host.set_process(false)  # the test steps the clock
	Net.mode = Net.Mode.SERVER
	Net.room_host = host


func after_each() -> void:
	Net.mode = Net.Mode.NONE
	Net.room_host = null
	fx.server.free()


func _hello() -> Dictionary:
	return {"protocol": Protocol.PROTOCOL_VERSION, "build": Protocol.BUILD_ID, "join_token": "t", "name": "x"}


func _connected() -> int:
	return fx.server.occupied_slots()


func _step(seconds: float) -> void:
	for i: int in int(seconds * 10.0):
		host._process(0.1)


func test_a_peer_gone_while_its_token_is_checked_is_never_admitted() -> void:
	host.on_server_attached(fx.server)
	host.on_hello(1, _hello())  # a real player
	orch.answer.emit()
	assert_eq(host.welcomed_peers(), [1] as Array[int])
	host.on_hello(2, _hello())  # joins, then drops before the orchestrator answers
	host.on_peer_disconnected(2)
	orch.answer.emit()
	assert_eq(host.welcomed_peers(), [1] as Array[int], "the dropped peer is not admitted")
	assert_eq(_connected(), 1, "and never counted as present")
	host.on_peer_disconnected(1)  # the last real player leaves
	_step(RoomHost.LEFT_EMPTY_CLOSE + 0.5)
	assert_eq(host.closed_reason, "empty", "the room closes")


func test_a_hello_queued_before_the_server_was_up_is_dropped_with_its_peer() -> void:
	host.on_hello(3, _hello())  # the match scene is still loading
	host.on_peer_disconnected(3)
	host.on_server_attached(fx.server)
	orch.answer.emit()
	assert_true(host.welcomed_peers().is_empty(), "nobody was admitted")
	assert_eq(_connected(), 0)
