# Credits

- Design and production: Patrick Cerny
- Engine: [Godot Engine](https://godotengine.org) (MIT)
- Testing: [GUT](https://github.com/bitwes/Gut) by Butch Wesley (MIT)

## 3D models (poly.pizza)

Picked by Patrick, downloaded from poly.pizza (`https://poly.pizza/m/<id>`), stored in
`assets/polypizza/`. The poly.pizza API and pages are not reachable from the build sandbox, so
the license column is what the model's own data shows (creator naming and export pipeline).
CC-BY models must keep their author named here.

| File | Model | id | Author | License |
|---|---|---|---|---|
| skin_01.glb | Wizardus Maximus | 6oDxK0wqyL | madtrollstudio | CC-BY 3.0 |
| skin_02.glb | Business Man | JFrLIKqvCH | Quaternius | CC0 (Quaternius rig and clips) |
| skin_03.glb | Warrior | RaWl2GJ0NZ | mastjie | CC0 |
| skin_04.glb | King | I1gTjmuK2m | Quaternius | CC0 (Quaternius rig and clips) |
| skin_05.glb | Man | HMnuH5geEG | Quaternius | CC0 (Quaternius rig and clips) |
| skin_06.glb | SWAT | Btfn3G5Xv4 | Quaternius | CC0 (Quaternius rig and clips) |
| poker_chip.glb | Poker chip | 2T3RWLeAudL | Poly by Google | CC-BY 3.0 |
| money_pile.glb | Cash Money - Big Pile | dZPTS7VMmqP | Evol-Love | CC-BY 3.0 |
| beer_empty.glb | Beer Mug | Zkyui3QLc9 | MilkAndBanana | CC0 |
| cone.glb | Cone | WoXpAJT0oD | J-Toastie | CC-BY 3.0 |
| seat.glb | Bar Stool | 2do92chR2k | Kenney | CC0 (Kenney Furniture Kit) |
| rug_blackjack.glb | Rug Round | jeDDiN69Ze | Kenney | CC0 (Kenney Furniture Kit) |
| couch.glb | Couch Medium | mWgQ94zhDZ | Quaternius | CC0 |
| flowers_01.glb | Flower Pot | Kgt363WkKd | Quaternius | CC0 |
| flowers_02.glb | Houseplant | bfLOqIV5uP | Quaternius | CC0 |
| flowers_03.glb | Houseplant | VtJh4Irl4w | Quaternius | CC0 |
| atm_shop.fbx | ATM | p4U0tSF5WN | J-Toastie | CC-BY 3.0 |
| revolver.glb | Revolver | 9C26wSpMS0 | Quaternius | CC0 |
| scratch_ticket.glb | Dollar | YmaCrICQe2 | J-Toastie | CC-BY 3.0 |
| coin_placeholder.glb | Coin | 7IrL01B97W | Quaternius | CC0 |
| bat.glb | Baseball bat | 6wSe56-sKXD | Poly by Google | CC-BY 3.0 |
| dog_leash.glb | Dog collar | fdF9rO_aCcq | Poly by Google | CC-BY 3.0 |
| beer_full.glb | BEER | 40Ke6-N0q7l | sugamo | CC-BY 3.0 |

Authors and licenses verified on the poly.pizza model pages on 2026-10-10. CC-BY 3.0 models need this
attribution kept in the shipped credits. atm_shop is the original FBX (poly.pizza only offered it as FBX).

## Other models

| File | Model | Source | Author | License |
|---|---|---|---|---|
| assets/casino/blackjack_table.dae | Half-moon blackjack table | sent by Patrick (Casino_Free pack) | Casino_Free pack | Patrick confirmed it may be shared publicly (2026-10-10) |
| assets/casino/roulette_table.fbx | Roulette wheel ("rolley casino", Rolley.fbx) | sent by Patrick | Rolley | Patrick confirmed it may be shared publicly (2026-10-10) |

Its camera and lights were stripped from the file. The table's texture files (BrushedIron02_4K, Metal007_4K, Wood067_8K) were not included, so it
uses flat casino colors. The roulette wheel carries its own textures; its floor plane, camera and
lights are dropped in game.

## Lucky Lounge surfaces and decor (CC0)

Picked from the 2026-10-06 texture research (notes in `/mnt/project-files/better-at-gambling/textures/NOTES.md`),
downscaled to 1K JPG by `tools/import_textures.sh`, applied client-side by `maps/lucky_lounge/lounge_decor.gd`.
All CC0 (public domain); credit lines kept anyway.

| Folder under `assets/textures/` | Source | Author / licence |
|---|---|---|
| casino_carpet/albedo.jpg | custom wine-red casino carpet (gold lattice), made for this project | Patrick Cerny / CC0 |
| casino_carpet/normal.jpg | Fabric026 (https://ambientcg.com/a/Fabric026) | ambientCG (Lennart Demes) / CC0 |
| checker_marble/ | Tiles074 (https://ambientcg.com/a/Tiles074) | ambientCG (Lennart Demes) / CC0 |
| herringbone_parquet/ | herringbone_parquet (https://polyhaven.com/a/herringbone_parquet) | Poly Haven (Rob Tuytel) / CC0 |
| damask_wallpaper/ | custom stylised damask, wine-on-wine and gold-on-black | Patrick Cerny / CC0 |
| wooden_panels/ | wooden_panels (https://polyhaven.com/a/wooden_panels) | Poly Haven / CC0 |
| black_marble/ | Marble016 (https://ambientcg.com/a/Marble016) | ambientCG (Lennart Demes) / CC0 |
| velvet/ | velour_velvet (https://polyhaven.com/a/velour_velvet) | Poly Haven / CC0 |
| brass/ | Metal048A (https://ambientcg.com/a/Metal048A) | ambientCG (Lennart Demes) / CC0 |
| coffered_ceiling/ | dark_paneled_wood (https://polyhaven.com/a/dark_paneled_wood) | Poly Haven / CC0 |

| File under `assets/models/` | Model | Source | Author / licence |
|---|---|---|---|
| quaternius_interior/Column_Round3.fbx | classical round column (the pillars) | Ultimate House Interior Pack (https://quaternius.com/packs/ultimatehomeinterior.html) | Quaternius / CC0 |
| quaternius_interior/Column_Round1.fbx | short column (statue pedestals in the VIP lounge) | same pack | Quaternius / CC0 |
| quaternius_interior/Window_Round1.fbx | arched window | same pack | Quaternius / CC0 |
| quaternius_interior/Window_Large1.fbx | large window (kept for later use) | same pack | Quaternius / CC0 |
| quaternius_interior/Curtains_Double.fbx | curtains (recoloured red velvet) | same pack | Quaternius / CC0 |
| quaternius_interior/Door_Double.fbx | double doors (staff door, VIP door, street door) | same pack | Quaternius / CC0 |
| polyhaven/ornate_mirror_01/ | gold baroque mirror (entrance hall) | https://polyhaven.com/a/ornate_mirror_01 | Poly Haven (Rico Cilliers) / CC0 |
| polyhaven/fancy_picture_frame_01/ | gold picture frame with painting (game floor walls) | https://polyhaven.com/a/fancy_picture_frame_01 | Poly Haven / CC0 |
| polyhaven/marble_bust_01/ | marble bust (VIP lounge) | https://polyhaven.com/a/marble_bust_01 | Poly Haven / CC0 |
| polyhaven/horse_statue_01/ | horse statue (VIP lounge) | https://polyhaven.com/a/horse_statue_01 | Poly Haven / CC0 |

## Playing cards

- `assets/cards/*.png`: card faces and back by Kenney (kenney.nl), CC0, taken from
  [simple-card-pile-ui](https://github.com/insideout-andrew/simple-card-pile-ui) by Andrew Vickerman (MIT, 2024).
  The 3D dealing code in `games/blackjack/table_cards.gd` follows that addon's approach.

## Sound effects

Kenney (kenney.nl), CC0: the `*-vN.ogg` files in `audio/sfx/` (see `audio/sfx/KENNEY_LICENSE.txt`), except the ones listed below.

Casino-floor music `audio/music/casino_base.ogg`: "base music game 2", supplied by Patrick Cerny.

Results music `audio/music/results_winners.ogg`: "Winners music" from 2:10, supplied by Patrick Cerny.

Supplied by Patrick Cerny for this game: `minor_win-v1.ogg`; `roulette_spin-v1.ogg`; `announcer_correct-vN.ogg` (announcer voice lines); `quiz_winner-v1.ogg`; `last_call_announce-v1.ogg`; `hot_table_announce-v1.ogg`; `card_deal-v1.ogg`; `slots_lever-v1.ogg`; `chips_in_pot-v1.ogg` (the chip part of his "Put Chips in Pot"); `slots_riser_1..3-v1.ogg` (his "Slots tripple win" riser, cut at its three onsets, 0.71 s apart).

`slots_no_match-v1.ogg`: "Two Tone" from *Casino Sounds* by Bjorn Lynne, supplied by Patrick Cerny (licence held by him).

`jackpot_prize-v1.ogg`: "8 Bit Prize Win" from *Casino Tones* by Callum Donaldson, supplied by Patrick Cerny (licence held by him).

## Fonts

Barlow Condensed, SIL Open Font License.
