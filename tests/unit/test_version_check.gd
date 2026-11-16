extends GutTest
## `VersionCheck`: version ordering, Steam's live-build verdict, the lobby mismatch text and the
## main menu's update card.


func test_compare_versions() -> void:
	assert_eq(VersionCheck.compare_versions("0.9.64", "0.9.63"), 1)
	assert_eq(VersionCheck.compare_versions("0.9.9", "0.9.10"), -1, "numbers, not text")
	assert_eq(VersionCheck.compare_versions("v0.9.64", "0.9.64"), 0, "a release tag's v")
	assert_eq(VersionCheck.compare_versions("1.0", "1.0.0"), 0)
	assert_eq(VersionCheck.compare_versions("1.0.0", "0.9.99"), 1)
	assert_eq(VersionCheck.compare_versions("0.4.0-m4", "0.4.0"), 0, "a suffix is ignored")


func test_steam_verdict_follows_the_live_branch() -> void:
	var branches: Array = [
		{"name": "beta", "build_id": 300, "flags": 2},
		{"name": "public", "build_id": 200, "flags": 1 | 2 | 16},
	]
	var v: Dictionary = VersionCheck.steam_verdict(150, branches)
	assert_true(v["outdated"], "the default branch has a newer live build")
	assert_eq(v["latest"], 200)
	assert_false(VersionCheck.steam_verdict(200, branches)["outdated"], "up to date")
	assert_false(VersionCheck.steam_verdict(250, branches)["outdated"], "newer than live (an uploaded build) is fine")
	branches[0]["flags"] = 2 | 8
	assert_true(VersionCheck.steam_verdict(250, branches)["outdated"], "a picked branch wins over the default one")
	assert_eq(VersionCheck.steam_verdict(250, branches)["branch"], "beta")


func test_steam_verdict_without_data_says_nothing() -> void:
	assert_eq(VersionCheck.steam_verdict(0, [{"build_id": 5, "flags": 1}]), {}, "no Steam build (dev copy)")
	assert_eq(VersionCheck.steam_verdict(5, []), {}, "Steam lists no branches")
	assert_eq(VersionCheck.steam_verdict(5, [{"build_id": 9, "flags": 2}]), {}, "no default or picked branch")


func test_runs_from_the_steam_folder() -> void:
	var svc: GDScript = load("res://services/steam_service.gd")
	var steam_dir: String = "C:\\Program Files (x86)\\Steam\\steamapps\\common\\Better at Gambling"
	assert_true(svc.call(&"runs_from", "C:/Program Files (x86)/Steam/steamapps/common/Better at Gambling/BetterAtGambling.exe", steam_dir))
	assert_true(svc.call(&"runs_from", "/home/a/.steam/steamapps/common/Better at Gambling/Better at Gambling.app/Contents/MacOS/Better at Gambling", "/home/a/.steam/steamapps/common/Better at Gambling/"))
	assert_false(svc.call(&"runs_from", "C:/Users/patri/Desktop/BetterAtGambling/BetterAtGambling.exe", steam_dir), "a GitHub copy")
	assert_false(svc.call(&"runs_from", "C:/Steam/steamapps/common/Better at Gambling 2/x.exe", "C:/Steam/steamapps/common/Better at Gambling"), "a folder that only starts the same")
	assert_false(svc.call(&"runs_from", "C:/x.exe", ""))


func test_lobby_mismatch_says_who_must_update() -> void:
	assert_string_contains(SteamParty.version_mismatch_text("99.0.0"), "Your game is out of date")
	assert_string_contains(SteamParty.version_mismatch_text("0.0.1"), "The host's game is out of date")


func test_banner_shows_only_when_behind() -> void:
	var b := UpdateBanner.new()
	add_child_autofree(b)
	b.show_verdict({"outdated": false, "text": "x"})
	assert_false(b.visible)
	b.show_verdict({"outdated": true, "text": VersionCheck.STEAM_TEXT})
	assert_true(b.visible)
	assert_string_contains(b.message(), "restart Steam")
	assert_string_contains(b.message(), Protocol.BUILD_ID)


func test_peer_build_marks_us_behind() -> void:
	var saved: Dictionary = VersionCheck.verdict
	VersionCheck.verdict = {}
	var vc := VersionCheck.new()
	add_child_autofree(vc)
	vc.note_peer_build(Protocol.BUILD_ID)
	assert_eq(VersionCheck.verdict, {}, "same version: nothing")
	vc.note_peer_build("0.0.1")
	assert_eq(VersionCheck.verdict, {}, "an older friend: nothing")
	vc.note_peer_build("99.0.0")
	assert_true(VersionCheck.verdict.get("outdated", false))
	assert_eq(VersionCheck.verdict.get("source"), &"peer")
	VersionCheck.verdict = saved
