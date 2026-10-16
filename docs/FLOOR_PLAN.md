# Floor plan: a new casino floor every round

Patrick: "Make it, that everytime the casino round starts, the games are randomized. So its not that
everything is always there, its random."

Every casino round of an online match (dedicated server or host-on-PC, both run a room server)
starts on a freshly drawn floor. Practice keeps the full floor. Minigames-only matches have no
casino floor, so nothing is drawn there.

## What is fixed, what is drawn

The Lucky Lounge's floor is a set of fixed **spots** (anchors). Each spot has a place, a facing and
a size class, and the full floor (Practice, menu panorama) puts its usual game on each one.

| Size class | Fits | Spots on the Lucky Lounge |
|---|---|---|
| `table` | blackjack, roulette, craps, Hi-Lo, the Wheel of Fortune, and any new table game (the default) | 8 on the floor, 2 in the VIP lounge |
| `cabinet` | slot machines | 12 on the floor, 2 in the VIP lounge |
| `big` | Plinko | 2 on the floor |

The spots come from `LuckyLounge.STATIONS`: every line whose game is not `fixed` is a spot of its
game's size (`GameDefinition.floor_footprint`), so the full floor is always one possible outcome.
Spot ids are `t1..t8`, `c1..c12`, `b1..b2`, `vt1..vt2`, `vc1..vc2` (numbered in STATIONS order).

These never change: the Race Hall and its horse race (`floor_footprint = fixed`), the waiting
room's play-money tables, the Odd Jobs cabinet, the Gift Shop, the bar, the settings tablet, the
jail and the walls. Dealers follow their tables.

## The draw

At every casino round start the server draws each spot afresh from its own seeded RNG (the match
seed, so a match replays exactly). Per area (casino floor, VIP lounge):

1. Each spot is closed with `empty_chance` (15 %), otherwise it gets a game of its size by weight,
   among the games that fit there (see "Room to stand" below).
2. Soft cap: at most `max_per_type` (2) tables of one game per area (cabinets are not capped).
3. If fewer than `min_filled` (60 %) of the area's spots are open, closed spots reopen until the
   minimum is met; the cap only gives way if the minimum can't be met without it. The room rules
   never give way: a spot where nothing fits stays closed.

## Room to stand

Tables are not all the same size (a craps table is 4.3 m long, the wheel stands on its own, the
spots by the east wall are tight), so the size class alone can't say what fits where. The draw
also checks the room (`FloorGeometry`):

- **Measured games.** When the map loads (`LuckyLounge.measure_floor`) it builds each drawable game's
  station once out of sight and takes the floor it covers in its own frame: its colliders, its
  chairs (+-0.3 m) and its dealer (+-0.35 m). Nothing to keep up by hand; a new game is measured too.
- **Floor areas** (`LuckyLounge.FLOOR_AREAS`): the casino floor, the VIP lounge and the west end of
  the entrance hall. A game has to lie wholly inside one.
- **Keep-outs** (`LuckyLounge.FLOOR_KEEP_OUT`): pillars, the bar and stools, the Gift Shop, Odd
  Jobs, the jail door, the Race Hall archway, the lobby and VIP doorways, plants, the VIP statues,
  the settings tablet, and a square round every guard and waiter route point so the patrols stay
  walkable.
- **Walkway** (`gap`, 0.35 m): two drawn games keep this much floor between their chairs. 0.35 m is
  the tightest pair on the full floor (craps and Hi-Lo), so the full floor stays a possible draw.

The server only measures when a map scene is loaded (room servers and the host always have one);
without measurements (unit and integration tests with a bare map definition) the size class alone
decides.

Nothing is guaranteed: any game may be missing in a round, and a spot may get the same game twice
in a row by chance. A closed spot is never left bare: table and Plinko spots get a velvet rope on
brass posts with a CLOSED TONIGHT sign, slot spots a potted plant (`FloorProps`).

When it happens:

- **Lobby opens** (and again on Play Again): the first round's floor stands behind the shut doors
  and is on the board while people wait.
- **Every regroup**: everyone is in the entrance hall behind the shut doors, the minigame already
  refunded every bet and stood everyone up, so the floor is switched there. Anyone still seated at
  a table that goes is stood up (`player_stood`, reason `floor_changed`) and its open bets refunded.

## Station ids

Stations keep game-named ids, numbered per game in spot order: `blackjack_1`, `slot_4`,
`vip_roulette_1`. A table keeps its logic (blackjack shoe and all) when its id and game stay; the
others close and new ones open. This kept every id-based path (HUD labels, items, dealers, tests,
autosit) unchanged. The waiting room (`fun_`) and the horse race keep their own ids.

## Players see it

- **TONIGHT'S FLOOR** board on the entrance hall's side of the lobby wall, right of the doors: the
  games on the floor with their counts, the VIP lounge's games, the Race Hall and how many spots are
  closed tonight.
- Feed line at the regroup: "The floor has changed! Tonight's games are on the board by the doors."

## On the wire

- `match_started`, `regroup_started` and `match_reset` carry `floor_plan: {round, stations:
  {station id: [game, spot id]}}` (`{}` in `regroup_started` when nothing was drawn).
- The snapshot carries `floor_plan` (late joiners and reconnects build the floor from it).
- Clients rebuild the map's stations, closed spots, dealers and board from it and take a fresh
  snapshot so tables that closed drop out of their cached station states. The host's map rebuilds
  synchronously from the server (`MatchServer.floor_changed`) so seats are known before anyone sits.
- The navmesh is baked again after each switch, so guards and the waiter path round the new tables.

## Tuning (data only)

`data/balance/floor_plan.tres` (`FloorPlanConfig`): `draw_in_rooms`, `draw_in_practice`,
`min_filled`, `empty_chance`, `max_per_type`, `capped_footprints`, `default_weight`, `weights`
(game id → weight; 0 takes a game off the floor), `gap` (walkway between drawn games, metres).
The floor areas and keep-outs are the map's (`LuckyLounge.FLOOR_AREAS`, `FLOOR_KEEP_OUT`). Dev and tests: `--floor random|full` or
`MatchScene.test_floor` override the room/Practice rule.

## Adding a table game

Register it in `data/registry/games.tres` as usual and add one line to `LuckyLounge.STATIONS` where
it stands on the full floor (that line becomes a new spot), plus its case in `_make_station` (or a
`station_scene`). It joins the draw automatically with `default_weight`. If it is not table-sized,
set `floor_footprint` in its `.tres` (`cabinet` for a slot-machine-sized box, `big` for something
Plinko-sized): a game is only ever put on spots of its own size, and only where its measured floor
fits. If its own spot is next to a wall, door or patrol point, check the keep-outs.
`tests/physics/test_floor_plan_scene.gd` checks that every spot's usual game fits and keeps the
walkway, builds every game on every spot the draw allows it on with the real colliders, and fails
on any overlap or a seat the navmesh can't reach.
