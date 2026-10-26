class_name FloorSite
extends Resource
## Where a map lets the floor generator put its games (docs/FLOOR_PLAN.md, `FloorGenerator`):
## the table pit (the table games, grouped in blocks of two back-to-back rows round a dealers'
## lane), the wall runs (slot banks, Plinko, kiosks with their backs to a wall) and the islands
## (open floor where one free-standing group may stand). World x, z on the floor; yaw in degrees
## (0: the players on the +z side, 90: +x, -90: -x, 180: -z). Filled in by the map
## (`LuckyLounge.floor_site`); a map without one has a floor that never changes.

## Id and name of the full floor (the generator's canonical draw: every game, every pit block,
## no dice): Practice, the menu panorama and the map as built stand on it.
@export var full_id: StringName = &"grand_hall"
@export var full_title: String = "The Grand Hall"
## The stations that never move (the horse race, the VIP lounge): their ids.
@export var fixed: Array[StringName] = []
## The pit: the line down the middle of the dealers' lane (z) and the lane's width (rect to rect,
## two beans side by side and some), and how far the rows' players' sides may reach north and
## south (z of their outer edges).
@export var lane_z: float = 0.0
@export var lane: float = 2.0
## How wide a bean is: two tables side by side in a row stand either closer than this, solid to
## solid (nobody squeezes through), or a lane's width apart (two beans side by side).
@export var bean_width: float = 0.84
@export var pit_north: float = -INF
@export var pit_south: float = INF
## The pit's block styles: each a list of x intervals (Vector2 from, to), one block each; aisles
## run between the blocks. The canonical draw takes the first style.
@export var pit_styles: Array = []
## Wall runs: {from: Vector2, to: Vector2, yaw: float, kinds: Array of footprints}: the line the
## backs stand on (axis-aligned, from one end to the other), which way the games face, and which
## size classes may stand there (`GameDefinition.floor_footprint`: cabinet, big, kiosk).
@export var walls: Array = []
## Islands: {rect: Rect2, yaws: Array of float, kinds: Array of footprints}: open floor where one
## free-standing group may stand (a slot island stands back to back, the others face a yaw).
@export var islands: Array = []
