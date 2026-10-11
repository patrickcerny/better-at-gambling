class_name TransportFactory
extends RefCounted
## Builds transports (§4.1). `opts.latency_ms`/`opts.loss` wrap the pipe in a DelayedTransport
## (tests and `--net-latency`/`--net-loss` dev flags only). `opts.transport` picks the pipe:
## "enet" (default, UDP to host:port) or "steam" (Steam Networking Messages to
## `opts.steam_id`, host mode); a NetTransport object is used as it is (tests).


static func server(port: int, max_clients: int, opts: Dictionary = {}) -> NetTransport:
	var given: Variant = opts.get("transport")
	if given is NetTransport:
		return _wrap(given as NetTransport, opts)
	var t := ENetTransport.new()
	if t.listen(port, max_clients, str(opts.get("bind_ip", "*"))) != OK:
		return null
	return _wrap(t, opts)


static func client(host: String, port: int, opts: Dictionary = {}) -> NetTransport:
	var given: Variant = opts.get("transport")
	if given is NetTransport:
		return _wrap(given as NetTransport, opts)
	if str(given) == "steam":
		var st := SteamTransport.new(opts.get("steam") as Object)
		if st.connect_to_user(int(opts.get("steam_id", 0))) != OK:
			return null
		return _wrap(st, opts)
	var t := ENetTransport.new()
	if t.connect_to(host, port) != OK:
		return null
	return _wrap(t, opts)


static func _wrap(t: NetTransport, opts: Dictionary) -> NetTransport:
	var latency: float = float(opts.get("latency_ms", 0.0))
	var loss: float = float(opts.get("loss", 0.0))
	if latency <= 0.0 and loss <= 0.0:
		return t
	return DelayedTransport.new(t, latency, loss, int(opts.get("seed", 1)))
