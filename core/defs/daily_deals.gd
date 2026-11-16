class_name DailyDeals
extends RefCounted
## The shop's DAILY DEALS (Patrick 2026-11-16: "Every day, rotate the featured skins for better
## prices"): a new set of featured pieces every UTC day, the same for every player and worked out
## offline from the date alone, each PERCENT_OFF cheaper while it is featured.
##
## Two kinds of offer: pieces for red Coins (the profile pays the deal price, `PlayerProfile.buy`)
## and premium pieces or sets for Gold Coins. A Gold deal is a second exchange recipe on the piece's
## Steam item definition (tools/steam/make_itemdefs.gd writes "3100x149;3100x104"), so Steam takes
## the lower price only once Steamworks holds those recipes: until then (`GOLD_LIVE` false) the Gold
## offers are featured at their normal price.
##
## Only things the shop sells are featured: never level-pass, Daily Spin, achievement or developer
## pieces, and never anything free.

## How much a deal takes off, in percent.
const PERCENT_OFF: int = 30
## Red-Coin offers a day.
const COIN_DEALS: int = 2
## Gold offers a day (a premium piece or a set).
const GOLD_DEALS: int = 1
## Whether Steamworks has the discounted exchange recipes (tools/steam/itemdefs.json uploaded):
## until then a Gold offer is featured at its normal price, as a lower one would be refused.
const GOLD_LIVE: bool = false

## Tests: the day to use instead of today (-1 = the clock).
static var fixed_day: int = -1
## Tests: no deals at all (every price is the normal one).
static var off: bool = false


## Today as a day number (UTC days since 1970): the same for every player.
static func today() -> int:
	if fixed_day >= 0:
		return fixed_day
	return int(Time.get_unix_time_from_system() / 86400.0)


## Seconds until the next day's deals.
static func seconds_left() -> int:
	var now: float = Time.get_unix_time_from_system()
	return maxi(0, int(ceil((floor(now / 86400.0) + 1.0) * 86400.0 - now)))


## "5H 12M" / "12M": how long today's deals still run.
static func time_left_text(seconds: int) -> String:
	var h: int = seconds / 3600
	var m: int = maxi(1, (seconds % 3600) / 60) if h == 0 else (seconds % 3600) / 60
	return "%dH %dM" % [h, m] if h > 0 else "%dM" % m


## A red-Coin piece the shop sells (no level wall, nothing special about how it is had).
static func coin_offer(d: CosmeticDef) -> bool:
	return d.coin_buyable() and d.level <= 0 and not d.dev_only and not d.wheel_only and d.achievement == &""


## A premium piece the shop sells for Gold Coins.
static func gold_offer(d: CosmeticDef) -> bool:
	return d.premium() and d.level <= 0 and not d.dev_only and not d.wheel_only and d.achievement == &""


## The day's offers: COIN_DEALS red-Coin pieces first, then GOLD_DEALS premium pieces or sets
## (ids of `CosmeticDef`s and `CosmeticPack`s). Picked from the day number alone.
static func ids(shop: CosmeticShop, day: int = -1) -> Array[StringName]:
	var out: Array[StringName] = []
	if shop == null or off:
		return out
	if day < 0:
		day = today()
	var coin_pool: Array[StringName] = []
	var gold_pool: Array[StringName] = []
	for d: CosmeticDef in shop.items:
		if coin_offer(d):
			coin_pool.append(d.id)
		elif gold_offer(d):
			gold_pool.append(d.id)
	for k: CosmeticPack in shop.packs:
		if k.gold > 0 and k.steam_item > 0:
			gold_pool.append(k.id)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("daily_deals_%d" % day)
	out.append_array(_pick(rng, coin_pool, COIN_DEALS))
	out.append_array(_pick(rng, gold_pool, GOLD_DEALS))
	return out


## `n` different ids from `pool`.
static func _pick(rng: RandomNumberGenerator, pool: Array[StringName], n: int) -> Array[StringName]:
	var left: Array[StringName] = pool.duplicate()
	var out: Array[StringName] = []
	while out.size() < n and not left.is_empty():
		out.append(left.pop_at(rng.randi_range(0, left.size() - 1)))
	return out


## Whether `id` is on deal on `day` (today by default), and its price really drops.
static func is_deal(shop: CosmeticShop, id: StringName, day: int = -1) -> bool:
	if not ids(shop, day).has(id):
		return false
	var d: CosmeticDef = shop.find(id)
	if d != null and d.coin_buyable():
		return true
	return GOLD_LIVE


## A price with the deal taken off (rounded to the nearest Coin, never below 1).
static func cut(price: int) -> int:
	if price <= 0:
		return price
	return maxi(1, (price * (100 - PERCENT_OFF) + 50) / 100)


## What piece `d` costs in red Coins on `day`.
static func coin_price(shop: CosmeticShop, d: CosmeticDef, day: int = -1) -> int:
	return cut(d.price) if d.coin_buyable() and is_deal(shop, d.id, day) else d.price


## What premium piece `d` costs in Gold Coins today.
static func gold_price(shop: CosmeticShop, d: CosmeticDef, day: int = -1) -> int:
	return cut(d.gold) if d.premium() and is_deal(shop, d.id, day) else d.gold


## What set `pack` costs in Gold Coins today.
static func pack_price(shop: CosmeticShop, pack: CosmeticPack, day: int = -1) -> int:
	return cut(pack.gold) if is_deal(shop, pack.id, day) else pack.gold
