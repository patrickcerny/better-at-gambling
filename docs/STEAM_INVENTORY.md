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
  item definitions with a price: Valve's price tiers (`price_category` "1;VLV100" / VLV200 /
  VLV500), so Steam sets a fitting price in every currency (Patrick 2026-11-15). The + next to the Gold in the shop opens the GOLD page; BUY WITH
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

## Daily Spin (Patrick 2026-11-16)

DAILY SPIN on the main menu opens a prize wheel (`DailySpinPanel`, `DailyWheelView`, data in
`core/defs/daily_wheel.gd`): one free spin every 20 hours. Nothing is paid for a spin, so it is
not a loot box. Prizes: red Coins (100 to 2,500), a mystery piece (a normal piece you don't own
yet), Gold Coins (5 / 10 / 25 / 50) and, at 0.3 %, the Fortune skin (`skin_fortune`, Steam item
208, `CosmeticDef.wheel_only`: never sold, only from the wheel).

- With Steam, Steam decides the spin: SPIN calls `triggerItemDrop(3200)`. 3200 is a
  `playtimegenerator` with `drop_window` 1200 minutes and `drop_max_per_window` 1, so Steam grants at
  most one prize per account per 20 hours whatever the client does, and picks it by the weights in
  its bundle. Prizes arrive as tokens: 3201-3207 (Coins, mystery piece) are consumed by the game and
  paid into profile.cfg; 3211-3214 (Gold) are exchanged for the bundles 3311-3314 (5/10/25/50 Gold
  Coins, `exchange` "3211x1" etc.), so Gold can only come out of a won token; the skin (208) is
  granted directly. Tokens left over (the game closed mid-payout) are paid on the next inventory read.
- Timer: the profile keeps the last spin (`[daily] last_spin`), measured in Steam's server time when
  Steam runs, so turning the PC clock does nothing. Without Steam (or until the item definitions are
  uploaded) the spin is local: Coins and mystery pieces only, the Gold and jackpot slices dimmed, and
  the PC clock counts (turning it forward to spin early locks the wheel once it is set back).
- Upload: the new definitions are in `tools/steam/itemdefs.json` (162 definitions). Not on Steam yet:
  needs Patrick's go. After uploading, check in the Steamworks item definition editor that 3200 shows
  as a playtime generator with the drop window.
