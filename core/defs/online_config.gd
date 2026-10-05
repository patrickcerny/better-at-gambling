class_name OnlineConfig
extends Resource
## Where the client finds the room orchestrator (§4.0 "Configuration"). The release build points
## at the owner's domain; `--orchestrator <url>` overrides it for development. Never an IP in code.

## Base URL of the orchestrator, e.g. https://play.example.com
@export var orchestrator_url: String = "http://127.0.0.1:8080"
