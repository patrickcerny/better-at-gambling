extends SceneTree
## Writes tools/steam/itemdefs.json from the cosmetics shop: one Steam Inventory item definition
## per paid outfit piece (`CosmeticDef.steam_item`) and one bundle per pack (`CosmeticPack`).
## Upload it in Steamworks (App 5623410 → Inventory Service → Item Definitions).
##   tools/godot/godot --headless --path . -s tools/steam/make_itemdefs.gd

const OUT: String = "res://tools/steam/itemdefs.json"
const APP_ID: int = 5623410  # SteamSvc.APP_ID


func _init() -> void:
	var data: Dictionary = itemdefs(CosmeticShop.default())
	var f := FileAccess.open(OUT, FileAccess.WRITE)
	f.store_string(JSON.stringify(data, "  ", false) + "\n")
	f.close()
	print("wrote %s (%d item definitions)" % [OUT, (data["items"] as Array).size()])
	quit()


## The whole file: {appid, items}.
static func itemdefs(shop: CosmeticShop) -> Dictionary:
	var items: Array = []
	for d: CosmeticDef in shop.items:
		if not d.steam_buyable():
			continue
		items.append({
			"itemdefid": d.steam_item,
			"type": "item",
			"name": d.display_name,
			"description": "%s for your bean in Better at Gambling.%s" % [String(d.kind).capitalize(), " Only sold here." if d.money_only else ""],
			"price": price(d.cents),
			"store_tags": String(d.kind),
			"tradable": false,
			"marketable": false,
		})
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
			"name": k.display_name,
			"description": "The whole %s outfit (%d pieces), cheaper than one by one." % [k.display_name, k.pieces.size()],
			"price": price(k.cents),
			"store_tags": "pack",
			"tradable": false,
			"marketable": false,
		})
	return {"appid": APP_ID, "items": items}


## A Steam price string: euro and dollar, same number ("1;EUR75,USD75").
static func price(cents: int) -> String:
	return "1;EUR%d,USD%d" % [cents, cents]
