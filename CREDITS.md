# Credits

- Design and production: Patrick Cerny
- Engine: [Godot Engine](https://godotengine.org) (MIT)
- Testing: [GUT](https://github.com/bitwes/Gut) by Butch Wesley (MIT)

## 3D models

Every 3D model in the game is our own: the props (chips, stools, sofas, plants, columns,
windows, curtains, doors, paintings, mirror, statues, the roulette wheel, the cash pile, the bat,
revolver and beer mugs) are built in code by `tools/models/prop_recipes.gd` and written to
`assets/models/own/` by `tools/models/build_models.gd`; the items are hand-built in
`items/item_art.gd`; the logo by `tools/logo/build_logo3d.py`. The painting in the frames and the
roulette number ring are painted by `tools/models/make_textures.py`. Design and production:
Patrick Cerny.

## Lucky Lounge surfaces (CC0)

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
