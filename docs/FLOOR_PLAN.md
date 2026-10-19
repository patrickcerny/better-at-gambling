# Floor layouts: a different casino floor every round

Patrick (0.9.11): "After every minigame, the games (and layout change). Dont think about the room
as games with fixed spots, rather have x amounts of rearrangements of the room (tested, with a good
usefull layout) and then rotate between these layouts." "There shouldn't be an out of order sign
if a game is not available. There should be just another layout that gets put in."

This replaces the random spot draw of 0.9.10. The design notes behind the layouts (how each game
wants to stand, the first sketches) are in `FLOOR_LAYOUTS.md` in the project files.

## What a layout is

A layout (`FloorLayout`, `data/floor_layouts/<id>.tres`) is a list of stations: station id →
[game, position, yaw degrees], the same form as `LuckyLounge.STATIONS`. It moves and turns the
casino floor's games only. The room never changes: the walls, the lobby doors, the VIP lounge and
its four stations, the Race Hall and its horse race (`LuckyLounge.FIXED_STATIONS`), the waiting
room's play-money tables, the Gift Shop, Odd Jobs, the megaphone stand, the jail and the pillars.
There is no bar any more (Patrick: "the casino bar (its useless)"), so its strip by the east wall is
floor like any other.

Yaw: 0 puts the players on the south side (+z) and the dealer or cabinet north; 180 flips it; 90
puts the players east, −90 west (its back to the east wall).

The layouts are listed, in order, in `data/balance/floor_plan.tres` (`FloorPlanConfig.layouts`).
The first one, The Grand Hall, is the full floor: `LuckyLounge.STATIONS` is that layout plus the
fixed stations (one source of truth, the layout file), and Practice, the menu panorama and the map
as built stand on it. Adding a layout is a new `.tres` listed there; nothing in code changes.

## How the games stand

- **Wheel of Fortune**: a signboard that only reads from the front, so its back is always to a
  wall or to the back of a slot bank, never to a walkway or the middle of the room.
- **Craps**: the players' long side faces a walkway; the stickman's side is against another craps
  table (The Pit) or open floor.
- **Blackjack**: dealers backed by a wall or by each other (The Salon's triangle, Wheel Night's
  table by the lobby wall), the round side to the open floor.
- **Roulette**: an island; two of them mirrored (yaw 0 and 180) when they share an aisle.
- **Hi-Lo**: corners and row ends.
- **Slots**: banks of three or more, back to back or with their backs to a wall.
- **Plinko**: on the north wall, where the drop is seen from far away.
- **Scratch cards**: a services counter, beside the Gift Shop (south of it on the east wall, or
  north of Odd Jobs) or against the lobby wall inside the casino. Never in the entrance hall.
- **Sword Tapper**: two round pedestals (`sword_1`, `sword_2`) side by side, 1.8 m apart, both
  facing the same way, the player standing on the open side. By the lobby wall with their
  backs to it, or a pair in open floor in front of a slot bank, so a big pull's light column is
  seen across the room; more than 3.5 m (the interact range) from the entrance-hall spawns, so E
  in the lobby never steps up to one through the wall. Never in the entrance hall.

## The layouts

Centres are world (x, z), north is −z, the lobby doors are at z 8.4 (x −2.75..2.75).

### The Grand Hall (`grand_hall`)

blackjack 3, craps 1, hilo 1, plinko 2, roulette 2, scratch 1, slots 12, sword_tapper 2, wheel 1

| Station | Game | Centre (x, z) | Yaw |
|---|---|---|---|
| slot_1..6 | slots | x -20, -17.5, -15, -12.5, -10, -7.5; z -13.5 | 180 |
| slot_7..12 | slots | x -20, -17.5, -15, -12.5, -10, -7.5; z -8.5 | 0 |
| plinko_1 | plinko | (11, -14.5) | 0 |
| plinko_2 | plinko | (17.5, -14.5) | 0 |
| hilo_1 | hilo | (18.6, -4.8) | 0 |
| craps_1 | craps | (14, -6) | 0 |
| scratch_1 | scratch | (20.45, 4.85) | -90 |
| roulette_1 | roulette | (-6, -3) | 0 |
| roulette_2 | roulette | (6, -3) | 180 |
| blackjack_1 | blackjack | (-16, 4) | 0 |
| blackjack_2 | blackjack | (-9, 4) | 0 |
| blackjack_3 | blackjack | (-2, 4) | 0 |
| wheel_1 | wheel | (14.5, 6.2) | 180 |
| sword_1 | sword_tapper | (6.2, 5.9) | 180 |
| sword_2 | sword_tapper | (8, 5.9) | 180 |

### Wheel Night (`wheel_night`)

blackjack 3, craps 1, plinko 2, roulette 2, scratch 1, slots 9, sword_tapper 2, wheel 1

| Station | Game | Centre (x, z) | Yaw |
|---|---|---|---|
| wheel_1 | wheel | (5.4, -13.8) | 0 |
| plinko_1 | plinko | (-6, -14.5) | 0 |
| plinko_2 | plinko | (11.5, -14.5) | 0 |
| slot_1..3 | slots | x -20, -18.7, -17.4; z -15.3 | 0 |
| slot_4..6 | slots | x -21; z -11, -9.7, -8.4 | 90 |
| slot_7..9 | slots | x -20, -18.7, -17.4; z 7.6 | 180 |
| blackjack_1 | blackjack | (-12, -7.6) | 0 |
| blackjack_2 | blackjack | (-5, -7.6) | 0 |
| craps_1 | craps | (13, -7) | 0 |
| roulette_1 | roulette | (-6.5, 3.6) | 0 |
| roulette_2 | roulette | (7, 3.8) | 180 |
| blackjack_3 | blackjack | (14, 6.3) | 180 |
| scratch_1 | scratch | (20.45, 4.85) | -90 |
| sword_1 | sword_tapper | (15.5, -3.2) | 0 |
| sword_2 | sword_tapper | (17.3, -3.2) | 0 |

### The Pit (`the_pit`)

blackjack 3, craps 2, hilo 1, plinko 2, roulette 1, scratch 1, slots 6, sword_tapper 2, wheel 1

| Station | Game | Centre (x, z) | Yaw |
|---|---|---|---|
| plinko_1 | plinko | (-17, -14.5) | 0 |
| plinko_2 | plinko | (-11, -14.5) | 0 |
| slot_1..6 | slots | x 4, 5.3, 6.6, 7.9, 9.2, 10.5; z -15.3 | 0 |
| blackjack_1 | blackjack | (-9, -6.5) | 0 |
| blackjack_2 | blackjack | (-2, -6.5) | 0 |
| blackjack_3 | blackjack | (5, -6.5) | 0 |
| craps_1 | craps | (15.2, -7.6) | 180 |
| craps_2 | craps | (15.2, -3) | 0 |
| wheel_1 | wheel | (-19.8, -4) | 90 |
| roulette_1 | roulette | (-10, 3) | 0 |
| hilo_1 | hilo | (8, 3.5) | 0 |
| scratch_1 | scratch | (5.6, 6.85) | 180 |
| sword_1 | sword_tapper | (15.3, 6.8) | 180 |
| sword_2 | sword_tapper | (17.1, 6.8) | 180 |

### The Arcade (`the_arcade`)

blackjack 1, hilo 1, plinko 2, roulette 1, scratch 1, slots 18, sword_tapper 2, wheel 1

| Station | Game | Centre (x, z) | Yaw |
|---|---|---|---|
| hilo_1 | hilo | (-18, -13.8) | 0 |
| wheel_1 | wheel | (-12.5, -13.8) | 0 |
| slot_1..3 | slots | x 3.6, 4.9, 6.2; z -15.3 | 0 |
| plinko_1 | plinko | (12.5, -14.5) | 0 |
| plinko_2 | plinko | (17.5, -14.5) | 0 |
| slot_4..6 | slots | x -20, -18.7, -17.4; z -9 | 180 |
| slot_7..9 | slots | x -20, -18.7, -17.4; z -7.9 | 0 |
| slot_10..12 | slots | x -10, -8.7, -7.4; z -9 | 180 |
| slot_13..15 | slots | x -10, -8.7, -7.4; z -7.9 | 0 |
| roulette_1 | roulette | (8, -5) | 0 |
| blackjack_1 | blackjack | (-5, 3) | 0 |
| slot_16..18 | slots | x 13, 14.3, 15.6; z 7.6 | 180 |
| scratch_1 | scratch | (20.45, 5.4) | -90 |
| sword_1 | sword_tapper | (9, 4.2) | 0 |
| sword_2 | sword_tapper | (10.8, 4.2) | 0 |

### The Long Room (`the_long_room`)

blackjack 3, craps 1, hilo 1, plinko 2, roulette 2, scratch 1, slots 16, sword_tapper 2, wheel 1

| Station | Game | Centre (x, z) | Yaw |
|---|---|---|---|
| plinko_1 | plinko | (-5, -14.5) | 0 |
| plinko_2 | plinko | (5, -14.5) | 0 |
| slot_1..10 | slots | x -21; z -13.5, -12.2, -10.9, -9.6, -6.1, -4.8, -3.5, 1.5, 2.8, 4.1 | 90 |
| slot_11..16 | slots | x 9.85; z -14.2, -12.9, -11.6, -10.3, -9, -7.7 | 90 |
| blackjack_1 | blackjack | (-8.6, -9.7) | 90 |
| craps_1 | craps | (-8.4, -5.3) | 90 |
| blackjack_2 | blackjack | (-8.6, 1.6) | 90 |
| blackjack_3 | blackjack | (-8.6, 5.9) | 90 |
| wheel_1 | wheel | (5.6, -9.9) | -90 |
| roulette_1 | roulette | (5, -4.7) | -90 |
| roulette_2 | roulette | (5, 0.9) | -90 |
| hilo_1 | hilo | (6, 6.05) | -90 |
| scratch_1 | scratch | (20.45, 5.4) | -90 |
| sword_1 | sword_tapper | (13.5, -5) | 0 |
| sword_2 | sword_tapper | (15.3, -5) | 0 |

### The Salon (`the_salon`)

blackjack 3, hilo 2, roulette 2, scratch 1, slots 9, sword_tapper 2, wheel 1

| Station | Game | Centre (x, z) | Yaw |
|---|---|---|---|
| roulette_1 | roulette | (-7, -12.5) | 0 |
| roulette_2 | roulette | (7, -12.5) | 180 |
| hilo_1 | hilo | (-18, -9.5) | 0 |
| hilo_2 | hilo | (16.5, -11.3) | 0 |
| blackjack_1 | blackjack | (-3.5, -6.7) | 180 |
| blackjack_2 | blackjack | (3.5, -6.7) | 180 |
| blackjack_3 | blackjack | (0, -2.9) | 0 |
| wheel_1 | wheel | (19.6, 5.9) | -90 |
| slot_1..9 | slots | x -19, -17.7, -16.4, -9, -7.7, -6.4, 8, 9.3, 10.6; z 7.6 | 180 |
| scratch_1 | scratch | (20.45, -4.4) | -90 |
| sword_1 | sword_tapper | (4, 3.5) | 0 |
| sword_2 | sword_tapper | (5.8, 3.5) | 0 |

## Fitting the room (the proof)

Every layout has to fit the real map before it can stand (`FloorPlan.problems`, `FloorGeometry`):

- **Measured games.** When the map loads (`LuckyLounge.measure_floor`) it builds each game's station
  once out of sight and takes the floor it covers in its own frame: its colliders, its chairs
  (±0.3 m) and its dealer (±0.35 m).
- **Floor area** (`LuckyLounge.FLOOR_AREAS`): the casino floor only. A game lies wholly inside it.
- **Keep-outs** (`LuckyLounge.FLOOR_SOLIDS` and `FLOOR_CLEAR`): the pillars (two on the floor, two
  in the lobby wall), a plant by the west wall, the megaphone stand, the Gift Shop, Odd Jobs and
  the plant beside it; and floor that must stay open: the jail door, the Race Hall archway, the
  lobby and VIP doorways and a square round every guard and waiter route point.
- **Gap** (`gap`, 0.35 m): two games of a layout keep this much floor between their chairs.
- **Walkway check.** The navmesh bake redone on a coarse grid (0.25 m cells), everything it walks
  round grown by the agent radius and flooded from inside the lobby doors
  (`LuckyLounge.FLOOR_ENTRIES`): every chair and every patrol point must be reached.

The server checks each layout once per match (about 50–90 ms each) and skips one that fails, with a
warning in the log. `tests/physics/test_floor_plan_scene.gd` builds every layout in the real match
scene against the real colliders and the baked navmesh and fails on any overlap, any chair whose
nearest walkable floor can't be walked to from the doors, a guard or waiter route point off the
navmesh, or the jail door, the Race Hall archway, the lobby doors, the VIP door or the megaphone
stand cut off. A layout that ships has passed it.

## The rotation

`FloorRotation`, like the minigame bag (`MinigameDirector`): the enabled layouts go into a bag
shuffled from the match seed (its own stream, so the rotation never shifts the match's other
random draws, and a match replays exactly).

- The lobby opening (and Play Again, which starts a fresh bag) takes the first layout: it stands
  behind the shut doors while people wait. Every regroup takes the next.
- No layout comes twice before the bag is empty, and a fresh bag never starts with the layout that
  just stood.
- **No closed spots.** A layout that can't be used is skipped and the next one in the bag is taken:
  a game it needs has weight 0 in `floor_plan.tres` (or is not registered), or it failed the fit
  check on this map. If no layout can be used, the first one stands. There are no ropes, CLOSED
  TONIGHT signs, plants on empty spots or boards any more.
- Practice keeps The Grand Hall (`rotate_in_practice` false); minigames-only matches have no casino
  floor and never change it.

When it happens:

- **Lobby opens** (and again on Play Again).
- **Every regroup**: everyone is in the entrance hall behind the shut doors, the minigame already
  refunded every bet and stood everyone up, so the floor is switched there. Anyone still seated at
  a table that goes or moves is stood up (`player_stood`, reason `floor_changed`) and its open bets
  refunded. A hot table that goes or moves cools down.

## Station ids

Stations keep game-named ids, numbered per game in each layout: `blackjack_1`, `slot_14`,
`craps_2`; the Sword Tapper's pedestals go by the short name `sword_1`, `sword_2`. A table keeps
its logic (blackjack shoe and all) only when its id, game, place and facing all stay; one that
moves is a fresh table in its new place (`StationManager.apply_stations` `moved`). The VIP lounge (`vip_`), the waiting room (`fun_`) and the horse race keep their own ids
and never move.

## Players see it

- The feed line at the regroup: "The floor has changed!"
- The doors open on the new floor.

## On the wire (PROTOCOL_VERSION 9)

- `match_started`, `regroup_started` and `match_reset` carry `floor_plan: {round, layout, stations:
  {station id: [game, [x, y, z], yaw degrees]}}` (`{}` in `regroup_started` when the floor did not
  change).
- The snapshot carries `floor_plan` too (late joiners and reconnects build the floor from it).
- Clients build the casino's stations from the payload's games, places and facings, not from
  `STATIONS`, and take a fresh snapshot so tables that went drop out of their cached station states.
  The host's map rebuilds synchronously from the server (`MatchServer.floor_changed`) so seats are
  known before anyone sits.
- The navmesh is baked again after each switch, so guards and the waiter path round the new tables.

## Tuning (data only)

`data/balance/floor_plan.tres` (`FloorPlanConfig`): `rotate_in_rooms`, `rotate_in_practice`,
`layouts` (in order; the first is the full floor), `weights` (game id → weight; 0 takes a game off
the floor and every layout that needs it is skipped), `gap`. A layout's `enabled = false` takes it
out of the rotation. Dev and tests: `--floor random|full|<layout id>` or `MatchScene.test_floor`
override the room/Practice rule (a layout id puts that layout in every round);
`tools/dev/tutorial_shot.gd --view floor --floor <layout id>` renders the floor from inside the
lobby doors.

## Adding a table game

Register it in `data/registry/games.tres` as usual, add its case in `LuckyLounge._make_station` (or a
`station_scene`), and place it in the layouts where it should stand (at least The Grand Hall if it
is on the full floor). `tests/physics/test_floor_plan_scene.gd` then proves every layout still fits.
A game that keeps a place of its own (like the horse race) sets `floor_footprint = fixed` and goes
in `LuckyLounge.FIXED_STATIONS` instead.
