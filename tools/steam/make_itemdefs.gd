extends SceneTree
## Writes tools/steam/itemdefs.json from the cosmetics shop (see `itemdefs`). Packs taken out of the shop
## stay listed, hidden (`RETIRED`): Steam never deletes an item definition.
## Upload it in Steamworks (App 5623410 → Inventory Service → Item Definitions).
##   tools/godot/godot --headless --path . -s tools/steam/make_itemdefs.gd

const OUT: String = "res://tools/steam/itemdefs.json"
const APP_ID: int = 5623410  # SteamSvc.APP_ID
## Pictures for the Steam item store and inventory (tools/steam/icons, served from the public repo).
const ICON_BASE: String = "https://raw.githubusercontent.com/patrickcerny/better-at-gambling/main/tools/steam/icons/"
## Item definitions already on Steam that the shop no longer sells: kept, hidden from the store.
const RETIRED: Array[Dictionary] = [
	{"itemdefid": 1009, "name": "Holiday Mode", "bundle": "107x1;120x1;138x1;156x1"},
]


func _init() -> void:
	var data: Dictionary = itemdefs(CosmeticShop.default())
	var f := FileAccess.open(OUT, FileAccess.WRITE)
	f.store_string(JSON.stringify(data, "  ", false) + "\n")
	f.close()
	print("wrote %s (%d item definitions)" % [OUT, (data["items"] as Array).size()])
	quit()


## The whole file: {appid, items}. Gold Coins (Patrick 2026-11-15): one Gold Coin item
## (`CoinPack.GOLD_ITEM`), gold packs sold for money that grant N of them, premium pieces and sets
## not sold for money but exchanged for Gold Coins ("exchange": "3100x75"), and the other pieces of
## a set as hidden items its bundle grants.
static func itemdefs(shop: CosmeticShop) -> Dictionary:
	var items: Array = []
	items.append({
		"itemdefid": CoinPack.GOLD_ITEM,
		"type": "item",
		"name": "Gold Coin",
		"description": "Spent on premium pieces and sets in the cosmetics shop of Better at Gambling.",
		"icon_url": ICON_BASE + "gold_coin.png",
		"icon_url_large": ICON_BASE + "gold_coin_large.png",
		"store_hidden": true,
		"tradable": false,
		"marketable": false,
	})
	for c: CoinPack in shop.coin_packs:
		items.append({
			"itemdefid": c.steam_item,
			"type": "bundle",
			"bundle": "%dx%d" % [CoinPack.GOLD_ITEM, c.gold],
			"name": "%d Gold Coins" % c.gold,
			"description": "%d Gold Coins for premium pieces and sets in the cosmetics shop of Better at Gambling." % c.gold,
			"price_category": price_category(c.cents),
			# The item store lists no item without a picture (2026-11-15: "1-3 of 3" and an empty page).
			"icon_url": ICON_BASE + "gold_%d.png" % c.gold,
			"icon_url_large": ICON_BASE + "gold_%d_large.png" % c.gold,
			"store_tags": "gold",
			"tradable": false,
			"marketable": false,
		})
	for d: CosmeticDef in shop.items:
		if d.steam_item <= 0:
			continue
		var row: Dictionary = {
			"itemdefid": d.steam_item,
			"type": "item",
			"name": d.display_name,
			"description": "%s for your bean in Better at Gambling." % String(d.kind).capitalize(),
			"store_hidden": true,
			"tradable": false,
			"marketable": false,
		}
		if d.premium():
			row["exchange"] = "%dx%d" % [CoinPack.GOLD_ITEM, d.gold]
		items.append(row)
	for k: CosmeticPack in shop.packs:
		var grants := PackedStringArray()
		for id: StringName in k.pieces:
			var d: CosmeticDef = shop.find(id)
			if d != null and d.steam_item > 0:
				grants.append("%dx1" % d.steam_item)
		items.append({
			"itemdefid": k.steam_item,
			"type": "bundle",
			"bundle": ";".join(grants),
			"exchange": "%dx%d" % [CoinPack.GOLD_ITEM, k.gold],
			"name": k.display_name,
			"description": "The whole %s outfit (%d pieces) for Gold Coins." % [k.display_name, grants.size()],
			"store_hidden": true,
			"tradable": false,
			"marketable": false,
		})
	for r: Dictionary in RETIRED:
		items.append({
			"itemdefid": r["itemdefid"],
			"type": "bundle",
			"bundle": r["bundle"],
			"name": r["name"],
			"description": "No longer sold.",
			"store_hidden": true,
			"tradable": false,
			"marketable": false,
		})
	return {"appid": APP_ID, "items": items}


## Valve's price tiers (US cents): Steam sets a fitting price in every currency (Patrick
## 2026-11-15: regional prices instead of fixed EUR/USD).
const VALVE_TIERS: Array[int] = [25, 50, 75, 100, 150, 200, 250, 300, 350, 400, 450, 500, 750, 1000, 1500, 2000, 2500, 3000, 3500, 4000, 4500, 5000, 7500, 10000]


## The Valve price tier for a reference price in euro cents ("1;VLV100" for 0,99 €): the nearest
## tier at or above it, with 0,99 counting as 1,00.
static func price_category(cents: int) -> String:
	for t: int in VALVE_TIERS:
		if t >= cents:
			return "1;VLV%d" % t
	return "1;VLV%d" % VALVE_TIERS[-1]


## A Steam price string: euro and dollar, same number ("1;EUR75,USD75").
static func price(cents: int) -> String:
	return "1;EUR%d,USD%d" % [cents, cents]
