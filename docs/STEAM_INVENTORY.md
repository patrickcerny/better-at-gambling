# Real-money cosmetics (Steam Inventory Service)

Patrick 2026-11-14: pieces cost 0,50 to 1 euro, some are only sold for money, full packs are
50 cents cheaper than all their pieces one by one. Direct purchase only: no loot boxes, no random
drops, no second currency (casino theme, Austrian/Belgian rules on paid randomness).

## How it works

- Catalog: `data/progression/cosmetics_shop.tres`. Every paid outfit piece has `cents` (reference
  euro price) and `steam_item` (its Steam item definition, 100+). `money_only` pieces have no
  Coins price. Packs (`CosmeticPack`, 1000+) are Steam bundles granting their pieces.
  Prices by Coins tier: up to 300 Coins = 0,50 €, up to 500 = 0,75 €, above = 1,00 €;
  money-only pieces 1,00 €; a pack = its pieces minus 0,50 €.
- `SteamSvc` (services/steam_service.gd) reads prices (`requestPrices`, the player's currency) and
  the inventory (`getAllItems`) on start, when the shop opens and after a purchase, and hands the
  owned pieces to `ProfileManager.set_steam_owned`. Steam is the record; nothing about Steam
  purchases is saved in profile.cfg. BUY WITH STEAM / BUY PACK call `startPurchase`, which opens
  the Steam overlay.
- Without Steam the Steam buttons are greyed out; the reference euro prices still show.

## Steamworks setup (once, and after catalog changes)

1. Regenerate the definitions: `tools/godot/godot --headless --path . -s tools/steam/make_itemdefs.gd`
   (a test fails when tools/steam/itemdefs.json is stale).
2. Steamworks, App 5623410: Community → Inventory Service → enable it.
3. Same page → Item Definitions → upload `tools/steam/itemdefs.json`, then publish.
4. Store page content: declare in-game purchases.
