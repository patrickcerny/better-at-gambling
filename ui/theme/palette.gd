class_name Palette
extends RefCounted
## The game's colour palette (docs/ART_DIRECTION.md). Use these, never ad-hoc colours.

const CASINO_BLACK := Color("#151414")
const WARM_CHARCOAL := Color("#24211F")
const CREAM := Color("#F2E6C9")
const CASINO_RED := Color("#C83D3D")
const FELT_GREEN := Color("#275E49")
const WARM_GOLD := Color("#D6A84B")
const VIP_BURGUNDY := Color("#681F2C")
const VIP_GOLD := Color("#E3B95C")
const MONEY_GREEN := Color("#68C26F")
const LOSS_RED := Color("#E55353")

## Eight colourblind-safe player colours (Okabe-Ito based, warmed to the palette).
const PLAYER_COLORS: Array[Color] = [
	Color("#E69F00"), Color("#56B4E9"), Color("#009E73"), Color("#F0E442"),
	Color("#0072B2"), Color("#D55E00"), Color("#CC79A7"), Color("#F2E6C9"),
]
const PLAYER_COLOR_NAMES: Array[String] = ["Orange", "Sky", "Green", "Yellow", "Blue", "Vermilion", "Pink", "Cream"]


## Player colour by index (wraps).
static func player_color(index: int) -> Color:
	return PLAYER_COLORS[posmod(index, PLAYER_COLORS.size())]


## Money delta colour.
static func delta_color(amount: int) -> Color:
	return MONEY_GREEN if amount >= 0 else LOSS_RED
