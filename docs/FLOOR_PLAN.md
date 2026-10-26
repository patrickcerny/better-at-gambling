# Floor layouts: a drawn casino floor every round

Patrick (0.9.16): "The floorlayouts are sometimes stupid to walk through. test them. [...] Group the
tablegames and make random layouts. theyre all about the same size so that should be easier for
you." Before that (0.9.11): "After every minigame, the games (and layout change)." "There shouldn't
be an out of order sign if a game is not available. There should be just another layout that gets
put in."

0.9.16 replaced the six hand-made layouts of 0.9.11 (`data/floor_layouts/*.tres`, gone) with a
floor generator (`FloorGenerator`) that draws a fresh floor every round from the match seed. The
design notes and the walk results of the old layouts are in `FLOOR_LAYOUTS.md` in the project
files.

## What a floor is

A floor (`FloorLayout`) is a list of stations: station id → [game, position, yaw degrees], the same
form as `LuckyLounge.STATIONS`. It moves and turns the casino floor's games only. The room never
changes: the walls, the lobby doors, the VIP lounge and its four stations, the Race Hall and its
horse race (`LuckyLounge.FIXED_STATIONS`), the waiting room's play-money tables, the Gift Shop, Odd
Jobs, the megaphone stand, the jail and the pillars. There is no bar (Patrick: "the casino bar (its
useless)").

Yaw: 0 puts the players on the south side (+z) and the dealer or cabinet north; 180 flips it; 90
puts the players east, −90 west (its back to the east wall). Centres are world (x, z), north is −z,
the lobby doors are at z 8.4 (x −2.75..2.75).

## The site: where things may stand (`FloorSite`, `LuckyLounge.floor_site()`)

Each game names its size class (`GameDefinition.floor_footprint`): `table` (blackjack, roulette,
craps, Hi-Lo, the wheel, and Hold'em when it registers), `cabinet` (slots), `big` (Plinko), `kiosk`
(scratch cards, the Sword Tapper) or `fixed` (the horse race; never on the drawn floor). The site
is the map's data, with no code path per game:

- **The pit** (the table games). Two rows either side of a lane at z −5.6, 2.0 m wide (two beans
  side by side): the north row faces north (yaw 180), the south row south (yaw 0), so the dealers
  stand back to back across the lane and the players sit outside on the aisles. Cross aisles cut
  the rows into blocks, in one of two styles drawn per round:
  A: x −17.6..−12, −7.2..7.2, 12..16.6; B: x −17.6..−12, −7.2..−1.1, 1.1..7.2, 12..16.6.
  A row's outer edge stays inside z −10.9..−0.3, so the aisles round the pit stay two beans wide.
- **Wall runs**: the north wall west of the VIP door (cabinets, big, kiosk; slots on the full
  floor), the north wall east of it (Plinko on the full floor), the west wall (cabinets) in two
  runs, the east wall by the jail (cabinets, kiosks) and north of it (kiosks), and the scratch
  counter's strip south of the Gift Shop.
- **Islands**: two strips between the pit and the lobby wall (x −17.6..−5 and x 5..13.2, z
  1.75..6.1) for kiosks and cabinet banks, facing south or north.
- **Out of the hall's reach**: no station's origin is south of z 5.45 (`FLOOR_HALL_REACH`). The
  interact range (3.5 m) works through the lobby wall, so E in the hall would grab it.

## How a floor is drawn (`FloorGenerator.draw`)

1. **Table games**: every table game that is on goes in the pit once, in random order, each into a
   random row that still has room; then 1–3 extra copies picked by weight (`extra_tables`,
   `weights`). A draw that can't seat every table game once is no draw.
2. **Rows**: a row's tables stand in an order that fits (any of its permutations), with the spare
   length split at random before and after. Two neighbours stand either tight (their solid parts
   closer than one bean, 0.84 m, so nobody tries to squeeze through) or a full lane apart (2.0 m
   between their solid parts); never a gap one bean only just fits through.
3. **Groups**: slots come in banks of 2–4 cabinets (9–15 machines in all), 1.3 m apart; the Sword
   Tapper's two pedestals as a pair 1.8 m apart; 1–2 Plinkos; one scratch counter.
4. **Wall runs and islands**: each group goes into a random wall run or island that takes its
   class and still has room (a slot island is two banks back to back), at a random place along it.
5. **Checks**: every draw then has to pass the fit check below. The server tries up to `draws` (6)
   seeds in a row (`seed`, `seed + 1`, ...) and the first that passes stands. If none does, the
   canonical draw over tonight's games stands, and if even that fails, the full floor.

The **full floor** (`FloorGenerator.full`, id `grand_hall`, "The Grand Hall") is the same generator
with no dice: every game, the first pit style, each table in the freest row, the extras of
`full_extras` (blackjack, roulette, blackjack), the run and island preferences of the site's `full`
lists, the spare length split evenly. Practice, the menu panorama and the map as built stand on it,
and `LuckyLounge.STATIONS` is it plus the fixed stations. Today it is:

| Station | Game | Centre (x, z) | Yaw |
|---|---|---|---|
| blackjack_1 | blackjack | (−14.8, −8.3) | 180 |
| blackjack_2 | blackjack | (−14.8, −2.9) | 0 |
| hilo_1 | hilo | (−2.78, −8.45) | 180 |
| roulette_1 | roulette | (2.35, −8.4) | 180 |
| craps_1 | craps | (−4.87, −2.5) | 0 |
| roulette_2 | roulette | (0.15, −2.8) | 0 |
| wheel_1 | wheel | (4.92, −2.7) | 0 |
| blackjack_3 | blackjack | (14.3, −8.3) | 180 |
| slot_1..12 | slots | x −20.58 .. −4.22 (banks of 4, 1.3 m apart), z −15.38 | 0 |
| slot_13..15 | slots | x −21.38; z −5.9, −7.2, −8.5 | 90 |
| plinko_1, plinko_2 | plinko | (7.64, −15.38), (14.66, −15.38) | 0 |
| scratch_1 | scratch | (20.48, 5.13) | −90 |
| sword_1, sword_2 | sword_tapper | (−12.2, 3.55), (−10.4, 3.55) | 0 |

A **new table game** (Hold'em registers as `holdem`, footprint `table`) needs no layout edits: the
generator puts it in the pit like the others, sized by the map's measurement of it (or a nominal
table, 5.2 × 4.3 m, until the map has measured it).

## Fitting the room (the proof)

Every floor has to fit the real map before it can stand (`FloorPlan.problems`,
`MatchServer.floor_problems`, `FloorGeometry`):

- **Measured games.** When the map loads (`LuckyLounge.measure_floor`) it builds each game's station
  once out of sight and takes the floor it covers in its own frame (its colliders, its chairs
  ±0.3 m, its dealer ±0.35 m) and its solid part (what people walk round).
- **Floor area** (`LuckyLounge.FLOOR_AREAS`): the casino floor only. A game lies wholly inside it.
- **Keep-outs** (`FLOOR_SOLIDS`, `FLOOR_CLEAR`): the pillars, a plant by the west wall, the
  megaphone stand, the Gift Shop, Odd Jobs and the plant beside it, the jail bars' collider; the
  jail door, the Race Hall archway and the lobby and VIP doorways; a 0.9 m square round every guard and waiter route point
  (`PATROL_CLEAR`); and no station origin in reach of the hall (`FLOOR_HALL_REACH`).
- **Gap** (`gap`, 0.35 m): two games keep this much floor between their chairs.
- **Walkway checks.** The navmesh bake redone on a coarse grid (0.25 m cells), flooded from inside
  the lobby doors: one bean (the game's agent radius) reaches every chair and patrol point, and two
  beans side by side (radius 0.84 m, `FloorGeometry.too_narrow`) reach every chair and doorway.

`tests/physics/test_floor_walkability.gd` walks the full floor, the canonical floor without craps
and 16 draws on navmeshes that the NavigationServer itself bakes (cell 0.14 m) for the game's
agent, for one bean (`PlayerAvatar.BODY_RADIUS` 0.42 m) and for two beans side by side (0.84 m).
It walks from the entrance-hall spawn to every chair and back, from every chair to every other
station, along the guard and waiter routes and through the doorways. Between neighbouring stations
no walk may be longer than 1.6 × the straight line (or 1.6 × 2 m when they stand closer).
`tests/physics/test_floor_plan_scene.gd` builds the full floor and drawn floors in the real match
scene. It fails on any overlap of colliders, on a chair the doors can't reach on the baked navmesh,
and on a route point, door or archway that is cut off. It also checks 120 more draws against the
room's real colliders (each game's measured solid parts where the draw puts them) without
building them.

## The draw each round

`FloorRotation` gives each round a seed from the match seed. It has its own stream, so the floor
never shifts the match's other random draws and a match replays exactly. It never gives the same
seed twice in a row. The floor's id is `floor_<seed>`.

- **No closed spots.** A game that is off (weight 0 in `floor_plan.tres`, or not registered) is
  simply not drawn. There are no ropes, CLOSED TONIGHT signs, plants on empty spots or boards.
- Practice keeps the full floor (`rotate_in_practice` false). Minigames-only matches have no casino
  floor and never change it.

When it happens:

- **Lobby opens** (and again on Play Again): the first floor stands behind the shut doors while
  people wait.
- **Every regroup**: everyone is in the entrance hall behind the shut doors, the minigame already
  refunded every bet and stood everyone up, so the floor is switched there. Anyone still seated at
  a table that goes or moves is stood up (`player_stood`, reason `floor_changed`) and its open bets
  refunded. A hot table that goes or moves cools down.

## Station ids

Stations have game-named ids, numbered per game on each floor: `blackjack_1`, `slot_14`,
`craps_2`; the Sword Tapper's pedestals go by the short name `sword_1`, `sword_2`. A table keeps
its logic (blackjack shoe and all) only when its id, game, place and facing all stay; one that
moves is a fresh table in its new place (`StationManager.apply_stations` `moved`). The VIP lounge
(`vip_`), the waiting room (`fun_`) and the horse race keep their own ids and never move.

## Players see it

- The feed line at the regroup: "The floor has changed!"
- The doors open on the new floor (the 3-2-1 on the doors is the only door text; no toasts).

## On the wire (since PROTOCOL_VERSION 9; unchanged by the drawn floors)

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

`data/balance/floor_plan.tres` (`FloorPlanConfig`):
- `rotate_in_rooms`, `rotate_in_practice`
- `extra_tables`: how many extra table copies (min, max)
- `full_extras`: the full floor's extra tables
- `cabinets`: how many slot machines (min, max)
- `bank`: machines per bank
- `bigs`: how many Plinkos
- `draws`: seeds tried per round before the fallback
- `weights`: game id → weight; 0 takes a game off the floor
- `gap`

The site (pit, runs, islands) is `LuckyLounge.floor_site()`.

For dev and tests, `--floor` or `MatchScene.test_floor` override the room/Practice rule. They take
`random`, `full`, `grand_hall`, `floor_<seed>` or a bare `<seed>`:
- `random` draws every round, in Practice too.
- `full` never draws.
- An id puts that floor in every round, so any drawn floor can be looked at again by its seed.

`tools/dev/tutorial_shot.gd --view floor --floor floor_<seed>` renders a floor from inside the lobby
doors. The server log names each round's floor (`floor 3: layout floor_123456, 30 stations`).

## Adding a game

Register it in `data/registry/games.tres` as usual with its `floor_footprint`, and add its case in
`LuckyLounge._make_station` (or a `station_scene`). The generator places it from then on, and
`tests/physics/test_floor_walkability.gd` and `test_floor_plan_scene.gd` prove the floors still
walk and fit. A game that keeps a place of its own (like the horse race) sets `floor_footprint =
fixed` and goes in `LuckyLounge.FIXED_STATIONS` instead.
