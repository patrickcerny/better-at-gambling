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
## lookup just says nothing. A lobby's version alone never counts: a friend may be on a newer GitHub
## build that isn't on Steam yet.

## {outdated, text, source}: `source` is &"steam" or &"github".
signal checked(verdict: Dictionary)

const GITHUB_LATEST: String = "https://api.github.com/repos/patrickcerny/better-at-gambling/releases/latest"
const TIMEOUT_S: float = 8.0
## EBetaBranchFlags (Steamworks SDK 1.60+), read from GodotSteam's constants when it has them.
const BRANCH_DEFAULT: int = 1
const BRANCH_SELECTED: int = 8

## The latest GitHub release's version, asked once per session ("" = not known).
static var _github_tag: String = ""
static var _github_asked: bool = false


func _ready() -> void:
	if DisplayServer.get_name() == "headless" or OS.get_cmdline_args().has("--no-version-check") or OS.get_cmdline_user_args().has("--no-version-check"):
		return
	_check.call_deferred()


## Steam is asked every time the menu opens (it's local and Patrick may set a build live while
## people play); GitHub once per session.
func _check() -> void:
	var steam: Dictionary = SteamSvc.steam_builds()
	if bool(steam.get("from_steam", false)):
		var v: Dictionary = steam_verdict(int(steam.get("installed", 0)), steam.get("branches", []) as Array, _steam_flag("BETA_BRANCH_SELECTED", BRANCH_SELECTED), _steam_flag("BETA_BRANCH_DEFAULT", BRANCH_DEFAULT))
		Log.info(&"version", "Steam build %d, live build %d (%s)" % [int(steam.get("installed", 0)), int(v.get("latest", 0)), str(v.get("branch", "?"))])
		if not v.is_empty():
			checked.emit({"outdated": bool(v["outdated"]), "text": STEAM_TEXT, "source": &"steam"})
		return  # a Steam copy never asks GitHub: GitHub runs ahead of what is live on Steam
	if steam_copy(OS.get_executable_path()):
		return  # a Steam install started without Steam: nothing to compare with
	if not _github_asked:
		_github_asked = true
		_github_tag = await _github_latest()
		Log.info(&"version", "latest GitHub release %s, this is %s" % [_github_tag, Protocol.BUILD_ID])
	if _github_tag == "" or not is_inside_tree():
		return
	checked.emit({"outdated": compare_versions(_github_tag, Protocol.BUILD_ID) > 0, "text": github_text(_github_tag), "source": &"github"})


## A copy inside a Steam library folder (steamapps/common), Steam running or not.
static func steam_copy(exe: String) -> bool:
	return exe.replace("\\", "/").to_lower().contains("/steamapps/common/")


static func _steam_flag(constant: StringName, fallback: int) -> int:
	if ClassDB.class_exists(&"Steam") and ClassDB.class_has_integer_constant(&"Steam", constant):
		return ClassDB.class_get_integer_constant(&"Steam", constant)
	return fallback


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
