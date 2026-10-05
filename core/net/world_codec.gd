class_name WorldCodec
extends RefCounted
## Binary encoding of the 20 Hz world stream (§4.1): every avatar's position, yaw and body state,
## ragdoll bodies of knocked-out/thrown players, guards, and props that are moving. Compact on
## purpose (≈20 bytes per standing player) to stay far below the 30 KB/s budget.
##
## Input/output dictionary:
## {t: float (server seconds), tick: int,
##  players: {id: {state: int, airborne: bool, pos: Vector3, yaw: float,
##                 rag?: {pos: Vector3, rot: Quaternion, parts: Array[Vector3] (4, world)}}},
##  guards: Array[{pos: Vector3, yaw: float, state: int}],
##  props: {index: {pos: Vector3, rot: Quaternion}}}

const VERSION: int = 1
const FLAG_AIRBORNE: int = 1
const FLAG_RAGDOLL: int = 2
const YAW_SCALE: float = 65535.0 / TAU
const QUAT_SCALE: float = 32767.0
const PART_SCALE: float = 1000.0  # millimetres; parts sit within ±32 m of the torso


## Encodes a world dictionary to bytes.
static func encode(w: Dictionary) -> PackedByteArray:
	var b := StreamPeerBuffer.new()
	b.put_u8(VERSION)
	b.put_u32(int(round(float(w.get("t", 0.0)) * 1000.0)) & 0xFFFFFFFF)
	b.put_u16(int(w.get("tick", 0)) & 0xFFFF)
	var players: Dictionary = w.get("players", {})
	b.put_u8(players.size())
	for id: Variant in players:
		var p: Dictionary = players[id]
		var rag: Dictionary = p.get("rag", {})
		var flags: int = (FLAG_AIRBORNE if bool(p.get("airborne", false)) else 0) | (FLAG_RAGDOLL if not rag.is_empty() else 0)
		b.put_u16(int(id))
		b.put_u8(int(p.get("state", 0)))
		b.put_u8(flags)
		_put_vec3(b, p.get("pos", Vector3.ZERO))
		b.put_u16(_yaw_to_u16(float(p.get("yaw", 0.0))))
		if not rag.is_empty():
			var torso: Vector3 = rag["pos"]
			_put_vec3(b, torso)
			_put_quat(b, rag["rot"])
			var parts: Array = rag.get("parts", [])
			for i: int in 4:
				var off: Vector3 = (parts[i] - torso) if i < parts.size() else Vector3.ZERO
				for c: float in [off.x, off.y, off.z]:
					b.put_16(clampi(int(round(c * PART_SCALE)), -32767, 32767))
	var guards: Array = w.get("guards", [])
	b.put_u8(guards.size())
	for g: Dictionary in guards:
		_put_vec3(b, g.get("pos", Vector3.ZERO))
		b.put_u16(_yaw_to_u16(float(g.get("yaw", 0.0))))
		b.put_u8(int(g.get("state", 0)))
	var props: Dictionary = w.get("props", {})
	b.put_u8(props.size())
	for idx: Variant in props:
		b.put_u16(int(idx))
		_put_vec3(b, props[idx]["pos"])
		_put_quat(b, props[idx]["rot"])
	return b.data_array


## Decodes bytes produced by `encode`. Returns {} on malformed input.
static func decode(bytes: PackedByteArray) -> Dictionary:
	if bytes.size() < 8:
		return {}
	var b := StreamPeerBuffer.new()
	b.data_array = bytes
	if b.get_u8() != VERSION:
		return {}
	var out: Dictionary = {"t": b.get_u32() / 1000.0, "tick": b.get_u16(), "players": {}, "guards": [], "props": {}}
	var n: int = b.get_u8()
	for i: int in n:
		if b.get_available_bytes() < 18:
			return {}
		var id: int = b.get_u16()
		var p: Dictionary = {"state": b.get_u8()}
		var flags: int = b.get_u8()
		p["airborne"] = (flags & FLAG_AIRBORNE) != 0
		p["pos"] = _get_vec3(b)
		p["yaw"] = _u16_to_yaw(b.get_u16())
		if flags & FLAG_RAGDOLL:
			if b.get_available_bytes() < 44:
				return {}
			var torso: Vector3 = _get_vec3(b)
			var rot: Quaternion = _get_quat(b)
			var parts: Array[Vector3] = []
			for k: int in 4:
				var off := Vector3(b.get_16(), b.get_16(), b.get_16()) / PART_SCALE
				parts.append(torso + off)
			p["rag"] = {"pos": torso, "rot": rot, "parts": parts}
		out["players"][id] = p
	var gn: int = b.get_u8()
	for i: int in gn:
		if b.get_available_bytes() < 15:
			return {}
		out["guards"].append({"pos": _get_vec3(b), "yaw": _u16_to_yaw(b.get_u16()), "state": b.get_u8()})
	var pn: int = b.get_u8()
	for i: int in pn:
		if b.get_available_bytes() < 22:
			return {}
		var idx: int = b.get_u16()
		out["props"][idx] = {"pos": _get_vec3(b), "rot": _get_quat(b)}
	return out


static func _put_vec3(b: StreamPeerBuffer, v: Vector3) -> void:
	b.put_float(v.x)
	b.put_float(v.y)
	b.put_float(v.z)


static func _get_vec3(b: StreamPeerBuffer) -> Vector3:
	return Vector3(b.get_float(), b.get_float(), b.get_float())


static func _put_quat(b: StreamPeerBuffer, q: Quaternion) -> void:
	var n: Quaternion = q.normalized()
	for c: float in [n.x, n.y, n.z, n.w]:
		b.put_16(clampi(int(round(c * QUAT_SCALE)), -32767, 32767))


static func _get_quat(b: StreamPeerBuffer) -> Quaternion:
	var q := Quaternion(b.get_16() / QUAT_SCALE, b.get_16() / QUAT_SCALE, b.get_16() / QUAT_SCALE, b.get_16() / QUAT_SCALE)
	return q.normalized() if q.length_squared() > 0.0001 else Quaternion.IDENTITY


static func _yaw_to_u16(yaw: float) -> int:
	return int(round(fposmod(yaw, TAU) * YAW_SCALE)) & 0xFFFF


static func _u16_to_yaw(v: int) -> float:
	return wrapf(v / YAW_SCALE, -PI, PI)
