class_name PlinkoStation
extends StationBase
## Wall-mounted Plinko board: 4 m tall, 12 peg rows, 13 slots at the bottom, 2 standing spots.

const ROWS: int = 12
const SLOTS: int = 13
const BOARD_W: float = 3.6
const BOARD_H: float = 4.0
const PEG_RADIUS: float = 0.05

## World x of each slot centre (local), left to right.
var slot_xs: Array[float] = []
## Local y of the top of the board where chips are released.
var drop_y: float = 0.0
var pegs_parent: Node3D


func _build_visuals() -> void:
	game_id = &"plinko"
	seat_count = 2
	interact_radius = 3.0
	_rug(Vector2(5.0, 4.0), Palette.VIP_BURGUNDY.darkened(0.3))
	# Back board (collidable so chips stay in plane via the chip's own axis lock; back wall for looks).
	GreyboxKit.box(self, Vector3(BOARD_W + 0.4, BOARD_H + 0.4, 0.2), Vector3(0, BOARD_H * 0.5 + 0.6, -0.25), Color("#3A2A1E"), "Backboard")
	GreyboxKit.box(self, Vector3(BOARD_W, BOARD_H, 0.05), Vector3(0, BOARD_H * 0.5 + 0.6, -0.14), Palette.CREAM.darkened(0.1), "Face", false)
	# Side rails.
	GreyboxKit.box(self, Vector3(0.1, BOARD_H, 0.3), Vector3(-BOARD_W * 0.5 - 0.05, BOARD_H * 0.5 + 0.6, 0.0), Palette.WARM_GOLD, "RailL")
	GreyboxKit.box(self, Vector3(0.1, BOARD_H, 0.3), Vector3(BOARD_W * 0.5 + 0.05, BOARD_H * 0.5 + 0.6, 0.0), Palette.WARM_GOLD, "RailR")
	pegs_parent = Node3D.new()
	pegs_parent.name = "Pegs"
	add_child(pegs_parent)
	var slot_w: float = BOARD_W / SLOTS
	var row_h: float = (BOARD_H - 1.2) / ROWS
	drop_y = 0.6 + BOARD_H - 0.3
	for r: int in ROWS:
		var count: int = SLOTS if r % 2 == 0 else SLOTS + 1
		var y: float = drop_y - 0.4 - r * row_h
		for c: int in count:
			var x: float = (c - (count - 1) * 0.5) * slot_w
			GreyboxKit.cylinder(pegs_parent, PEG_RADIUS, 0.25, Vector3(x, y, 0.0), Palette.WARM_GOLD, "Peg", true, 0.6).rotation.x = PI * 0.5
	# Slot dividers and labels row at the bottom.
	for s: int in SLOTS + 1:
		var x: float = (s - SLOTS * 0.5) * slot_w
		GreyboxKit.box(self, Vector3(0.04, 0.5, 0.3), Vector3(x, 0.6 + 0.25, 0.0), Palette.CASINO_RED, "Divider")
	for s: int in SLOTS:
		slot_xs.append((s - (SLOTS - 1) * 0.5) * slot_w)
	# Floor of the board (chips rest here) and a lip at the front.
	GreyboxKit.box(self, Vector3(BOARD_W + 0.2, 0.1, 0.4), Vector3(0, 0.55, 0.0), Color("#3A2A1E"), "Tray")
	GreyboxKit.box(self, Vector3(BOARD_W + 0.2, BOARD_H + 0.2, 0.02), Vector3(0, BOARD_H * 0.5 + 0.6, 0.16), Color(1, 1, 1, 0.0), "Glass")
	_add_seat(Vector3(-0.8, 0, 2.2), 0.0)
	_add_seat(Vector3(0.8, 0, 2.2), 0.0)
	camera_anchor = Node3D.new()
	camera_anchor.name = "CameraAnchor"
	camera_anchor.position = Vector3(0, 2.4, 3.2)
	camera_anchor.rotation.x = deg_to_rad(-5.0)
	add_child(camera_anchor)
	(get_node("Glass/Mesh") as MeshInstance3D).visible = false
