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

## Player (and bean) colours, `Cosmetics.COLOR_COUNT` of them. The first eight are colourblind-safe
## (Okabe-Ito based, warmed to the palette), free and what the server hands out; the rest are
## bought with Coins in the cosmetics shop (data/progression/cosmetics_shop.tres).
const PLAYER_COLORS: Array[Color] = [
	Color("#E69F00"), Color("#56B4E9"), Color("#009E73"), Color("#F0E442"),
	Color("#0072B2"), Color("#D55E00"), Color("#CC79A7"), Color("#F2E6C9"),
	Color("#B3263E"), Color("#8FE3C3"), Color("#B7A3E8"), Color("#1F8A8A"),
	Color("#A6D94A"), Color("#3A3533"), Color("#C9CED4"), Color("#F2C14E"),
]
const PLAYER_COLOR_NAMES: Array[String] = [
	"Orange", "Sky", "Green", "Yellow", "Blue", "Vermilion", "Pink", "Cream",
	"Ruby", "Mint", "Lavender", "Teal", "Lime", "Onyx", "Silver", "Gold",
]
## The Coins (out-of-match currency) gold.
const COIN_GOLD := Color("#F5C542")


## Player colour by index (wraps).
static func player_color(index: int) -> Color:
	return PLAYER_COLORS[posmod(index, PLAYER_COLORS.size())]


## The bean colour of a player's wire dictionary (`bean_color`, falling back to the slot colour).
static func bean_color(p: Dictionary) -> Color:
	return player_color(int(p.get("bean_color", p.get("color", 0))))


## Money delta colour.
static func delta_color(amount: int) -> Color:
	return MONEY_GREEN if amount >= 0 else LOSS_RED
