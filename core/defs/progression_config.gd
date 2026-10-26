class_name ProgressionConfig
extends Resource
## Out-of-match progression (docs/GDD.md "Progression"): the XP a finished match is worth, the
## level curve and the Coins earned with it. Data: data/progression/progression.tres. The server
## turns a match into a per-player breakdown with `Progression.breakdown`; each client adds its own
## row to its local profile (`PlayerProfile`). Coins are never in-match money: the tables only
## take $ (which resets every match).

const PATH: String = "res://data/progression/progression.tres"

@export_group("XP per match")
## For finishing a match at all.
@export var xp_match: int = 100
## By final placement (index 0 = 1st); places past the end get the last entry.
@export var xp_by_rank: PackedInt32Array = PackedInt32Array([120, 80, 50, 30, 20])
## Per minigame finished in first place.
@export var xp_per_minigame_win: int = 30
## Profit (final $ above the starting $) worth 1 XP, and the most XP profit can give.
@export var money_per_xp: int = 20
@export var xp_money_cap: int = 100
## Per table hand / round played (a `round_result`), and the most hands can give.
@export var xp_per_hand: int = 2
@export var xp_hands_cap: int = 60
## Practice (solo, in-process) earns at this rate.
@export_range(0.0, 1.0) var practice_rate: float = 0.5

@export_group("Level curve")
## XP from level L to L+1 below `soft_cap_level`: early_base + early_step * (L - 1).
@export var early_base: int = 100
@export var early_step: int = 35
## From this level on the curve slows: late_base + late_step * (L - soft_cap_level).
@export var soft_cap_level: int = 10
@export var late_base: int = 450
@export var late_step: int = 50
@export var max_level: int = 99

@export_group("Coins")
## Coins per XP earned in a match (rounded down), and for every level gained.
@export var coins_per_xp: float = 0.1
@export var level_up_coins: int = 50

static var _default: ProgressionConfig = null


## The shipped config (loaded once).
static func default() -> ProgressionConfig:
	if _default == null:
		_default = load(PATH) as ProgressionConfig
		if _default == null:
			_default = ProgressionConfig.new()
	return _default


## XP needed to go from `level` to `level + 1` (0 at the max level).
func xp_to_next(level: int) -> int:
	if level >= max_level:
		return 0
	if level < soft_cap_level:
		return early_base + early_step * (maxi(level, 1) - 1)
	return late_base + late_step * (level - soft_cap_level)


## Total XP needed to reach `level` from level 1.
func xp_for_level(level: int) -> int:
	var total: int = 0
	for l: int in range(1, clampi(level, 1, max_level)):
		total += xp_to_next(l)
	return total


## The level `total_xp` reaches (1 .. max_level).
func level_for_xp(total_xp: int) -> int:
	var level: int = 1
	var need: int = 0
	while level < max_level:
		need += xp_to_next(level)
		if total_xp < need:
			break
		level += 1
	return level


## XP the most XP a profile can hold (reaching the max level).
func max_xp() -> int:
	return xp_for_level(max_level)
