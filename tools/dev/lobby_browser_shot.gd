extends Control
## Dev: the main menu's full-screen PUBLIC LOBBIES (or FRIENDS' LOBBIES with --friends) filled with
## made-up lobbies, for look-dev of the small lobby cards with the players' heads.
## Run with scripts/screenshot.sh res://tools/dev/lobby_browser_shot.tscn lobbies 120 [--friends] [--lobbies N].


func _ready() -> void:
	var args := Cmdline.parse(OS.get_cmdline_user_args())
	var menu: Control = (load("res://ui/menus/main_menu.tscn") as PackedScene).instantiate()
	menu.set(&"load_match", false)
	add_child(menu)
	var names: Array = ["Patrick", "Ekvimsa", "Stefafo", "Lucky Lu", "Big Stack", "Mo", "Zed", "Ana", "Kai", "Rio"]
	var outfits: Array = [["hat_fedora"], [], ["hat_cone"], ["hat_crown"], [], ["hat_cowboy"], [], []]
	var lobbies: Array[Dictionary] = []
	for i: int in args.get_int("lobbies", 11):
		var n: int = 1 + (i * 3) % 8
		var beans: Array = []
		for j: int in n:
			beans.append({"n": names[(i + j) % names.size()], "c": (i + j) % 8, "o": outfits[(i + j) % outfits.size()], "l": j == 0})
		var info: Dictionary = LobbyInfo.parse(JSON.stringify({"mode": "casino" if i % 3 else "minigames", "mg": 5, "gm": 3, "items": i % 2 == 0, "picked": 16, "all": 16, "beans": beans, "playing": i == 2}))
		lobbies.append(SteamSvc.public_lobby_entry(100 + i, "%s's lobby" % names[i % names.size()], n, 8, info, "0.9.40" if i == 4 else Protocol.BUILD_ID))
	if args.has_flag("friends"):
		menu.call(&"_open_list", menu.get(&"friends_screen"))
		var parties: Array[Dictionary] = []
		for l: Dictionary in lobbies.slice(0, 3):
			parties.append({"lobby": l["lobby"], "friends": ["King Katić"], "party": l["name"], "build": l["build"], "members": l["members"], "max": 8, "info": l["info"]})
		menu.call(&"_fill_friends", parties)
	else:
		menu.call(&"_open_list", menu.get(&"browse_screen"))
		menu.call(&"_fill_browse", lobbies)
	(menu.get(&"browse_screen") as LobbyListScreen).focus_first()
