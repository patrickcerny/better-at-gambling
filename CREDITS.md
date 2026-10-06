# Credits

- Design and production: Patrick Cerny
- Engine: [Godot Engine](https://godotengine.org) (MIT)
- Testing: [GUT](https://github.com/bitwes/Gut) by Butch Wesley (MIT)

## 3D models (poly.pizza)

Picked by Patrick, downloaded from poly.pizza (`https://poly.pizza/m/<id>`), stored in
`assets/polypizza/`. The poly.pizza API and pages are not reachable from the build sandbox, so
the license column is what the model's own data shows (creator naming and export pipeline).
Rows marked **check** need the author and license copied from the model page; CC-BY models must
name their author here before release.

| File | Model | id | Author | License |
|---|---|---|---|---|
| skin_01.glb | Wizardus Maximus | 6oDxK0wqyL | **check** | **check** |
| skin_02.glb | Business Man | JFrLIKqvCH | Quaternius | CC0 (Quaternius rig and clips) |
| skin_03.glb | Warrior | RaWl2GJ0NZ | **check** | **check** |
| skin_04.glb | King | I1gTjmuK2m | Quaternius | CC0 (Quaternius rig and clips) |
| skin_05.glb | Man | HMnuH5geEG | Quaternius | CC0 (Quaternius rig and clips) |
| skin_06.glb | SWAT | Btfn3G5Xv4 | Quaternius | CC0 (Quaternius rig and clips) |
| poker_chip.glb | Poker chip | 2T3RWLeAudL | **check** | **check** |
| money_pile.glb | Money pile | dZPTS7VMmqP | **check** | **check** |
| beer_empty.glb | Beer Mug | Zkyui3QLc9 | **check** | **check** |
| cone.glb | Cone | WoXpAJT0oD | **check** | **check** |
| seat.glb | Bar Stool | 2do92chR2k | Kenney | CC0 (Kenney Furniture Kit) |
| rug_blackjack.glb | Rug Round | jeDDiN69Ze | Kenney | CC0 (Kenney Furniture Kit) |
| couch.glb | Couch Medium | mWgQ94zhDZ | Quaternius | CC0 |
| flowers_01.glb | Flower Pot | Kgt363WkKd | Quaternius | CC0 |
| flowers_02.glb | Houseplant | bfLOqIV5uP | Quaternius | CC0 |
| flowers_03.glb | Houseplant | VtJh4Irl4w | Quaternius | CC0 |

Still to come (see docs/MODELS.md): atm_shop, revolver, scratch_ticket, coin_placeholder, bat,
dog_leash, beer_full.

## Other models

| File | Model | Source | Author | License |
|---|---|---|---|---|
| assets/casino/blackjack_table.dae | Half-moon blackjack table | sent by Patrick (Casino_Free pack) | **check** | **check** |
| assets/casino/roulette_table.fbx | Roulette wheel ("rolley casino", Rolley.fbx) | sent by Patrick | **check** | **check** |

Its camera and lights were stripped from the file. The table's texture files (BrushedIron02_4K, Metal007_4K, Wood067_8K) were not included, so it
uses flat casino colors. The roulette wheel carries its own textures; its floor plane, camera and
lights are dropped in game.

## Playing cards

- `assets/cards/*.png`: card faces and back by Kenney (kenney.nl), CC0, taken from
  [simple-card-pile-ui](https://github.com/insideout-andrew/simple-card-pile-ui) by Andrew Vickerman (MIT, 2024).
  The 3D dealing code in `games/blackjack/table_cards.gd` follows that addon's approach.

## Sound effects

Kenney (kenney.nl), CC0: the `*-vN.ogg` files in `audio/sfx/` (see `audio/sfx/KENNEY_LICENSE.txt`), except the ones listed below.

Casino-floor music `audio/music/casino_base.ogg`: "base music game 2", supplied by Patrick Cerny.

Results music `audio/music/results_winners.ogg`: "Winners music" from 2:10, supplied by Patrick Cerny.

Supplied by Patrick Cerny for this game: `minor_win-v1.ogg`; `hot_table_announce-v1.ogg`; `card_deal-v1.ogg`; `slots_lever-v1.ogg`; `chips_in_pot-v1.ogg` (the chip part of his "Put Chips in Pot"); `slots_riser_1..3-v1.ogg` (his "Slots tripple win" riser, cut at its three onsets, 0.71 s apart).

`slots_no_match-v1.ogg`: "Two Tone" from *Casino Sounds* by Bjorn Lynne, supplied by Patrick Cerny (licence held by him).

`jackpot_prize-v1.ogg`: "8 Bit Prize Win" from *Casino Tones* by Callum Donaldson, supplied by Patrick Cerny (licence held by him).

## Fonts

Barlow Condensed, SIL Open Font License.
