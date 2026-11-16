extends Control
## Dev: the shared minigame scoreboard (MinigameScoreboard) in a few looks side by side: points with
## locked-in checks, hearts with a knocked-out player, and an 8-player compact board after a score
## change (the cards glide). scripts/screenshot.sh res://tools/dev/scoreboard_shot.tscn board 90


func _ready() -> void:
	var bg := ColorRect.new()
	bg.color = Color("#141210")
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var state := ClientMatchState.new()
	var names: Array = ["Patrick", "Ekvimsa", "Stefafo", "Big Wendy", "Snake Eyes", "Lena-Marie", "Chip", "Dice"]
	for pid: int in range(1, 9):
		state.players[pid] = {"name": names[pid - 1], "color": pid - 1, "bean_color": pid - 1}
	var a := MinigameScoreboard.new("SCORE", "round wins · total breaks ties").bind(state, 1)
	a.position = Vector2(40, 40)
	a.size = Vector2(420, 0)
	add_child(a)
	var rows: Array = [
		{"player": 2, "score": 2, "detail": "31 total", "status": &"done"},
		{"player": 1, "score": 1, "detail": "20 total", "status": &"done"},
		{"player": 3, "score": 0, "detail": "12 total", "status": &"waiting"},
	]
	MinigameScoreboard.rank_rows(rows)
	a.set_rows(rows)

	var b := MinigameScoreboard.new("HEARTS").bind(state, 1)
	b.position = Vector2(500, 40)
	b.size = Vector2(400, 0)
	add_child(b)
	b.set_rows([
		{"player": 7, "hearts": 3, "max_hearts": 3, "status": &"done", "leader": true},
		{"player": 1, "hearts": 2, "max_hearts": 3, "status": &"done"},
		{"player": 8, "hearts": 2, "max_hearts": 3, "status": &"waiting"},
		{"player": 5, "hearts": 1, "max_hearts": 3, "status": &"waiting"},
		{"player": 4, "hearts": 0, "max_hearts": 3, "status": &"out", "tag": "OUT", "tag_color": Palette.LOSS_RED},
	])

	var c := MinigameScoreboard.new("SCORES").bind(state, 1)
	c.position = Vector2(940, 40)
	c.size = Vector2(400, 0)
	add_child(c)
	var r8: Array = []
	for pid: int in range(1, 9):
		r8.append({"player": pid, "score": (9 - pid) * 100, "status": &"done" if pid % 2 == 0 else &""})
	MinigameScoreboard.rank_rows(r8)
	c.set_rows(r8)
	await get_tree().create_timer(0.3).timeout
	r8[5]["score"] = 1200
	r8[5]["tag"] = "+900"
	r8[5]["tag_color"] = Palette.MONEY_GREEN
	r8.sort_custom(func(x: Dictionary, y: Dictionary) -> bool: return int(x["score"]) > int(y["score"]))
	MinigameScoreboard.rank_rows(r8)
	c.set_rows(r8)
