class_name MinigameControls
extends RefCounted
## What each minigame's controls are, for its rules card (MinigameBriefing): one row per control,
## [keyboard + mouse, gamepad, what it does]. `{action}` is filled with that action's binding on
## the device (so rebinding shows up); "" means the device has no way to do it.

const MOVE: Array[String] = ["{move_forward}{move_left}{move_back}{move_right}", "{move_forward}", "Move"]
const JUMP: Array[String] = ["{jump}", "{jump}", "Jump"]

const ROWS: Dictionary = {
	&"quiz": [
		["1 – 4 / Click", "A / B / X / Y", "Lock in an answer (fast = more points)"],
	],
	&"lonely_number": [
		["Click", "D-pad + A", "Pick a number on the board"],
		["0 – 9 + Enter", "", "Or type it in"],
	],
	&"roulette_royale": [
		["1 / 2 / 3", "B / X / A", "Call RED / BLACK / GREEN"],
		["Click", "", "Or click a colour"],
	],
	&"split_or_steal": [
		["1", "A", "SPLIT"],
		["2", "B", "STEAL"],
		["{push_to_talk}", "{push_to_talk}", "Talk them round (voice)"],
	],
	&"bust_or_bank": [
		["{bj_hit}", "{bj_hit}", "HIT: take one more card"],
		["{bj_stand}", "{bj_stand}", "STAND: lock your hand"],
	],
	&"vote_race": [
		["1 – 9 / Click", "D-pad + A", "Vote for another racer"],
	],
	&"find_the_lady": [
		["1 – 4 / Click", "D-pad + A", "Pick the Queen's card"],
	],
	&"forehead_poker": [
		["1", "A", "STAY"],
		["2", "B", "FOLD"],
		["Mouse", "Right stick", "Look round the table"],
	],
	&"spy": [
		["Type + Enter", "A: keyboard", "Say your clue word on your turn"],
		["V", "Y", "Call a vote"],
		["1 – 9 / Click", "D-pad + A", "Vote someone out"],
	],
	&"pass_the_bomb": [
		MOVE, JUMP,
		["{interact}", "{interact}", "Tag the bean in front: pass the bomb"],
	],
	&"bat_heist": [
		MOVE,
		["{grab}", "{grab}", "Swing the bat / click fast to steal coins"],
		["{shove}", "{shove}", "Grab a bean, again to throw"],
	],
	&"last_seat": [
		MOVE,
		["{interact} / {grab}", "{interact} / {grab}", "Sit on the stool next to you when the music stops"],
		["{shove}", "{shove}", "Shove"],
	],
	&"grab_your_hand": [
		MOVE,
		["Walk over", "Walk over", "Pick up a card (5 max)"],
		["1 – 5 / Wheel", "D-pad ◀ ▶", "Choose a card in your hand"],
		["{interact}", "{interact}", "Drop the chosen card"],
		["{shove}", "{shove}", "Shove: they drop a card"],
	],
	&"roulette_sumo": [
		MOVE, JUMP,
		["{shove}", "{shove}", "Push"],
	],
	&"dodge_the_dice": [
		MOVE,
		["{jump}", "{jump}", "Jump the ledges and out of the chutes"],
	],
	&"jackpot_climb": [
		MOVE, JUMP,
		["{interact}", "{interact}", "Swing your bat at a climber"],
	],
}


## The rows for a minigame with the bindings filled in for both devices:
## [{"key": "E", "pad": "X", "what": "..."}], or [] for an unknown id.
static func rows(id: StringName) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for row: Variant in ROWS.get(id, []):
		var r: Array = row
		out.append({
			"key": InputGlyphs.fill_for(str(r[0]), false),
			"pad": InputGlyphs.pad_text(InputGlyphs.fill_for(str(r[1]), true)),
			"what": str(r[2]),
		})
	return out

