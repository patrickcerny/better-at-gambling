# poly.pizza models to download

Patrick's picks (2026-10-05), 23 files. Download each one as GLB into `assets/polypizza/<file>.glb` and
record its author and license in `CREDITS.md`. poly.pizza blocks the cloud sandbox, so the
download has to run on Patrick's PC.

| File | poly.pizza id | Use |
|---|---|---|
| skin_01 .. skin_06 | 6oDxK0wqyL, JFrLIKqvCH, RaWl2GJ0NZ, I1gTjmuK2m, HMnuH5geEG, Btfn3G5Xv4 | Player skins |
| poker_chip | 2T3RWLeAudL | Chips |
| money_pile | dZPTS7VMmqP | Money piles, also next to Plinko when the jackpot is big |
| atm_shop | p4U0tSF5WN | Gift shop kiosk |
| revolver | 9C26wSpMS0 | Russian roulette (replaces J3i9KDQ3kt, which is not used) |
| scratch_ticket | YmaCrICQe2 | Scratch ticket item |
| coin_placeholder | 7IrL01B97W | Default model for every item without its own |
| bat | 6wSe56-sKXD | Baseball bat item |
| dog_leash | fdF9rO_aCcq | Dog collar item |
| beer_full | 40Ke6-N0q7l | Beer item |
| beer_empty | Zkyui3QLc9 | Beer item after drinking |
| flowers_01 .. flowers_03 | Kgt363WkKd, bfLOqIV5uP, VtJh4Irl4w | Decoration |
| seat | 2do92chR2k | Seat at every game (link text said 8rVLUvWcsga; the link itself is 2do92chR2k) |
| rug_blackjack | jeDDiN69Ze | Under the blackjack tables |
| couch | mWgQ94zhDZ | Decoration |
| cone | WoXpAJT0oD | Blocks a game that is out of order / not open |

Page URL: `https://poly.pizza/m/<id>`.

## Lucky Lounge decor models (shipped, CC0)

Under `assets/models/`, placed by `maps/lucky_lounge/lounge_decor.gd` (client only; see CREDITS.md for
the licence lines). Loaded through `PropModels` ids: `column` (Quaternius Column_Round3, the pillars),
`pedestal` (Column_Round1, statue bases), `window_arch` (Window_Round1), `window_large` (Window_Large1,
unused yet), `curtains` (Curtains_Double), `door_double` (Door_Double), `mirror` (Poly Haven
ornate_mirror_01), `picture` (fancy_picture_frame_01), `bust` (marble_bust_01), `horse` (horse_statue_01).
Surface textures live in `assets/textures/<name>/` (1K JPG, `tools/import_textures.sh` regenerates them
from the research folder).
