extends Node
## `Net` autoload: owns the multiplayer peer and connection lifecycle.
##
## M0 stub; ENet client/server and room-code joins are implemented in M3.

## Emitted when a connection to a server is established.
signal connected
## Emitted when the connection drops or fails.
signal disconnected(reason: String)


## True while this process runs as the dedicated server.
func is_server() -> bool:
	return multiplayer.has_multiplayer_peer() and multiplayer.is_server()
