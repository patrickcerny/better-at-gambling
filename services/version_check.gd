class_name VersionCheck
extends Node
## "Is this game out of date?" (Patrick 2026-11-16: "warning if youre a version behind and you
## start the game"). The main menu adds one of these; `checked` fires once with the verdict and the
## menu shows `UpdateBanner` when the game is behind.
##
## Where "the latest version" comes from depends on how the game was started:
## - Started from the Steam install (the normal case): Steam itself knows. `getAppBuildId` is the
##   build this install has, `getBetaInfo` lists the app's branches with the build each one has live
##   (the branch the player picked, else the default one). A higher live build than ours means
##   Steam has an update this copy hasn't got (Steam not restarted, the update queued, the game
##   started from its folder). This follows what is LIVE on Steam, not what is only uploaded, and
##   not the GitHub releases, which run ahead of Steam.
## - Any other copy (a GitHub release zip, e.g. the desktop copy): the latest GitHub release's tag.
## Nothing is asked without a window (tests, the room server) or with `--no-version-check`; a failed
## lookup just says nothing. The verdict is kept for the session (the menu is rebuilt after
## every match). Lobbies from a newer version in the friends list also count (`note_peer_build`).

## {outdated, text, source}: `source` is &"steam", &"github" or &"peer".
signal checked(verdict: Dictionary)

const GITHUB_LATEST: String = "https://api.github.com/repos/patrickcerny/better-at-gambling/releases/latest"
const TIMEOUT_S: float = 8.0
## EBetaBranchFlags (Steamworks SDK 1.60+), read from GodotSteam's constants when it has them.
const BRANCH_DEFAULT: int = 1
const BRANCH_SELECTED: int = 8

## The verdict of this session ({} = not known yet).
static var verdict: Dictionary = {}


func _ready() -> void:
	if not verdict.is_empty():
		checked.emit.call_deferred(verdict)
		return
	if DisplayServer.get_name() == "headless" or OS.get_cmdline_args().has("--no-version-check") or OS.get_cmdline_user_args().has("--no-version-check"):
		return
	_check.call_deferred()


func _check() -> void:
	var steam: Dictionary = SteamSvc.steam_builds()
	if bool(steam.get("from_steam", false)):
		var v: Dictionary = steam_verdict(int(steam.get("installed", 0)), steam.get("branches", []) as Array, _steam_flag("BETA_BRANCH_SELECTED", BRANCH_SELECTED), _steam_flag("BETA_BRANCH_DEFAULT", BRANCH_DEFAULT))
		Log.info(&"version", "Steam build %d, live build %d (%s)" % [int(steam.get("installed", 0)), int(v.get("latest", 0)), str(v.get("branch", "?"))])
		if not v.is_empty():
			_finish({"outdated": bool(v["outdated"]), "text": STEAM_TEXT, "source": &"steam"})
		return  # a Steam copy never asks GitHub: GitHub runs ahead of what is live on Steam
	var tag: String = await _github_latest()
	if tag == "":
		return
	Log.info(&"version", "latest GitHub release %s, this is %s" % [tag, Protocol.BUILD_ID])
	var behind: bool = compare_versions(tag, Protocol.BUILD_ID) > 0
	_finish({"outdated": behind, "text": github_text(tag), "source": &"github"})


static func _steam_flag(constant: StringName, fallback: int) -> int:
	if ClassDB.class_exists(&"Steam") and ClassDB.class_has_integer_constant(&"Steam", constant):
		return ClassDB.class_get_integer_constant(&"Steam", constant)
	return fallback


func _finish(v: Dictionary) -> void:
	verdict = v
	checked.emit(v)


## A friend's lobby runs `build`: newer than ours means we are behind, whatever Steam said.
func note_peer_build(build: String) -> void:
	if build == "" or compare_versions(build, Protocol.BUILD_ID) <= 0:
		return
	if bool(verdict.get("outdated", false)):
		return
	_finish({"outdated": true, "text": peer_text(build), "source": &"peer"})


func _github_latest() -> String:
	var req := HTTPRequest.new()
	req.timeout = TIMEOUT_S
	add_child(req)
	var err: Error = req.request(GITHUB_LATEST, ["Accept: application/vnd.github+json", "User-Agent: BetterAtGambling/%s" % Protocol.BUILD_ID])
	if err != OK:
		req.queue_free()
		return ""
	var res: Array = await req.request_completed
	req.queue_free()
	if int(res[0]) != HTTPRequest.RESULT_SUCCESS or int(res[1]) != 200:
		Log.info(&"version", "GitHub release lookup failed (%d/%d)" % [int(res[0]), int(res[1])])
		return ""
	var body: Variant = JSON.parse_string((res[3] as PackedByteArray).get_string_from_utf8())
	if typeof(body) != TYPE_DICTIONARY:
		return ""
	return str((body as Dictionary).get("tag_name", "")).trim_prefix("v")


const STEAM_TEXT: String = "Steam has a newer version of the game. Quit, restart Steam and let it update, or you can't play online with everyone else."


static func github_text(latest: String) -> String:
	return "Version %s is out, you have %s. Download the new version to keep playing online with everyone else." % [latest, Protocol.BUILD_ID]


static func peer_text(build: String) -> String:
	return "Your friends play version %s, you have %s. Quit and restart Steam to update." % [build, Protocol.BUILD_ID]


## Steam's view of this install: {installed (build id), latest (live build id of the branch we
## follow), branch, outdated} or {} when Steam doesn't say. `branches` is GodotSteam's
## `getBetaInfo()`: [{build_id, flags, name, ...}].
static func steam_verdict(installed: int, branches: Array, selected_flag: int = BRANCH_SELECTED, default_flag: int = BRANCH_DEFAULT) -> Dictionary:
	if installed <= 0:
		return {}
	var target: Dictionary = {}
	for flag: int in [selected_flag, default_flag]:
		for b: Variant in branches:
			if typeof(b) == TYPE_DICTIONARY and int((b as Dictionary).get("flags", 0)) & flag != 0:
				target = b
				break
		if not target.is_empty():
			break
	var latest: int = int(target.get("build_id", 0))
	if latest <= 0:
		return {}
	return {"installed": installed, "latest": latest, "branch": str(target.get("name", "")), "outdated": latest > installed}


## -1, 0 or 1 like `a <=> b` for dotted versions ("0.9.64", "v1.0.0"; anything after a "-" ignored).
static func compare_versions(a: String, b: String) -> int:
	var pa: PackedStringArray = a.strip_edges().trim_prefix("v").get_slice("-", 0).split(".")
	var pb: PackedStringArray = b.strip_edges().trim_prefix("v").get_slice("-", 0).split(".")
	for i: int in maxi(pa.size(), pb.size()):
		var x: int = pa[i].to_int() if i < pa.size() else 0
		var y: int = pb[i].to_int() if i < pb.size() else 0
		if x != y:
			return 1 if x > y else -1
	return 0
