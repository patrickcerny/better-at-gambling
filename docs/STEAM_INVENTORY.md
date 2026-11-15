# Gold Coins and premium cosmetics (Steam Inventory Service)

Patrick 2026-11-15: two currencies. Red Coins are earned by playing (matches, every level up) and
buy the normal pieces. Gold Coins only come for real money and buy the premium pieces and the sets.
Direct purchase only: no loot boxes, no random drops (casino theme, Austrian/Belgian rules on paid
randomness). Before that (2026-11-14) pieces were sold one by one for 0,50 to 1 euro; that was
never uploaded to Steam.

## How it works

- Catalog: `data/progression/cosmetics_shop.tres`. Normal pieces have `price` (red Coins), saved in
  profile.cfg. Premium pieces have `gold` (Gold Coins, 50 to 200; skins 149/199) and `steam_item`
  (100+). Sets (`CosmeticPack`, 1000+) have `gold` and are Steam bundles granting their pieces, so
  every non-free piece of a set has a `steam_item` too (hidden, only granted by the set).
- Gold Coin: item definition 3100 (`CoinPack.GOLD_ITEM`). Gold packs (`CoinPack`, 3000+: 100 / 220 /
  600 Gold for 0,99 / 1,99 / 4,99 €) are bundles granting that many Gold Coins; they are the only
  item definitions with a price. The + next to the Gold in the shop opens the GOLD page; BUY WITH
  STEAM calls `startPurchase` (Steam overlay).
- Premium pieces and sets carry an `exchange` recipe ("3100x75"). BUY FOR N GOLD calls
  `SteamSvc.buy_with_gold`, which picks Gold Coin stacks (`gold_inputs`) and calls `exchangeItems`;
  Steam takes the coins and grants the piece. The balance and what was bought stay in the Steam
  inventory (nothing about Gold is saved in profile.cfg), read on start, when the shop opens and
  after each purchase or exchange (`SteamSvc.gold`, `ProfileManager.set_steam_owned`).
- Without Steam there is no Gold: premium pieces and sets say GOLD NEEDS STEAM.
- Gold Rush (level 25) and Rainbow (level 50) skins are also free at that level (`CosmeticDef.level`).
- Retired item definitions are never reused: 1009 (Holiday Mode) stays in itemdefs.json as
  `store_hidden`.

## Steamworks setup (once, and after catalog changes)

1. Regenerate the definitions: `tools/godot/godot --headless --path . -s tools/steam/make_itemdefs.gd`
   (a test fails when tools/steam/itemdefs.json is stale).
2. Steamworks, App 5623410: Community → Inventory Service → enable it.
3. Same page → Item Definitions → upload `tools/steam/itemdefs.json`, then publish.
4. Store page content: declare in-game purchases.
