class_name HttpJson
extends Node
## Minimal JSON-over-HTTP client for the room orchestrator (§4.0): one HTTPRequest per call,
## awaited by the caller. Never logs request bodies (they carry tickets and secrets).

const TIMEOUT_S: float = 8.0


## POSTs `body` as JSON. Returns {status: int (0 on network failure), body: Dictionary}.
func post(url: String, body: Dictionary) -> Dictionary:
	return await _request(url, HTTPClient.METHOD_POST, JSON.stringify(body))


## GETs a JSON document.
func fetch(url: String) -> Dictionary:
	return await _request(url, HTTPClient.METHOD_GET, "")


func _request(url: String, method: HTTPClient.Method, data: String) -> Dictionary:
	var req := HTTPRequest.new()
	req.timeout = TIMEOUT_S
	add_child(req)
	var err: Error = req.request(url, ["Content-Type: application/json", "Accept: application/json"], method, data)
	if err != OK:
		req.queue_free()
		return {"status": 0, "body": {"error": "network", "message": "Could not reach %s" % url.get_base_dir()}}
	var res: Array = await req.request_completed
	req.queue_free()
	var result: int = res[0]
	var code: int = res[1]
	var raw: PackedByteArray = res[3]
	if result != HTTPRequest.RESULT_SUCCESS:
		return {"status": 0, "body": {"error": "network", "message": "Could not reach the server (%d)." % result}}
	var parsed: Variant = JSON.parse_string(raw.get_string_from_utf8())
	return {"status": code, "body": parsed if typeof(parsed) == TYPE_DICTIONARY else {}}
