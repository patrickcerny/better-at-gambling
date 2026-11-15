extends SceneTree
## Writes tools/steam/itemdefs.json from the cosmetics shop (see `itemdefs`). Packs taken out of the shop
## stay listed, hidden (`RETIRED`): Steam never deletes an item definition.
## Upload it in Steamworks (App 5623410 → Inventory Service → Item Definitions).
##   tools/godot/godot --headless --path . -s tools/steam/make_itemdefs.gd

const OUT: String = "res://tools/steam/itemdefs.json"
const APP_ID: int = 5623410  # SteamSvc.APP_ID
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
			"price": price(c.cents),
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


## A Steam price string: euro and dollar, same number ("1;EUR75,USD75").
static func price(cents: int) -> String:
	return "1;EUR%d,USD%d" % [cents, cents]
