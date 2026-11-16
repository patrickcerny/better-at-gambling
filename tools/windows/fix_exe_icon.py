#!/usr/bin/env python3
"""Gives the exported .exe's icon group its GODOT_ICON name back.

Godot 4.7.2's Windows export (application/modify_resources) writes our icon into the .exe but
leaves the RT_GROUP_ICON entry with an empty name. The engine registers its window class with
LoadIcon(hInstance, "GODOT_ICON"), which then finds nothing, so the Windows taskbar falls back
to the generic application icon (Explorer still shows the right one: it takes the first group).

This writes the name "GODOT_ICON" into the unused tail of the .rsrc section and points the
entry at it. Pure stdlib, edits the file in place, does nothing if the name is already right.
Usage: tools/windows/fix_exe_icon.py build/windows/BetterAtGambling.exe
"""
import struct
import sys

WANT = "GODOT_ICON"
RT_GROUP_ICON = 14


def main(path: str) -> int:
	with open(path, "rb") as f:
		data = bytearray(f.read())
	pe = struct.unpack_from("<I", data, 0x3C)[0]
	if data[pe:pe + 4] != b"PE\0\0":
		sys.exit(f"{path}: not a PE file")
	n_sections = struct.unpack_from("<H", data, pe + 6)[0]
	opt_size = struct.unpack_from("<H", data, pe + 20)[0]
	opt = pe + 24
	if struct.unpack_from("<H", data, opt)[0] != 0x20B:
		sys.exit(f"{path}: not a PE32+ image")
	checksum_at = opt + 64
	res_dir_at = opt + 112 + 2 * 8  # data directory #2 = resources
	res_rva, res_size = struct.unpack_from("<II", data, res_dir_at)
	sec = None
	for i in range(n_sections):
		s = opt + opt_size + 40 * i
		vsize, va, raw_size, raw_ptr = struct.unpack_from("<IIII", data, s + 8)
		if va == res_rva:
			sec = (s, vsize, raw_size, raw_ptr)
	if sec is None:
		sys.exit(f"{path}: no resource section")
	sec_hdr, vsize, raw_size, base = sec

	def directory(off: int):
		named, ids = struct.unpack_from("<HH", data, base + off + 12)
		for k in range(named + ids):
			yield base + off + 16 + 8 * k

	def name_of(entry: int):
		name = struct.unpack_from("<I", data, entry)[0]
		if not name & 0x80000000:
			return name
		at = base + (name & 0x7FFFFFFF)
		n = struct.unpack_from("<H", data, at)[0]
		return data[at + 2:at + 2 + 2 * n].decode("utf-16-le")

	group_dir = None
	for entry in directory(0):
		if name_of(entry) == RT_GROUP_ICON:
			group_dir = struct.unpack_from("<I", data, entry + 4)[0] & 0x7FFFFFFF
	if group_dir is None:
		sys.exit(f"{path}: no icon group resource")
	entries = list(directory(group_dir))
	current = name_of(entries[0])
	if current == WANT:
		print(f"{path}: icon group already named {WANT}")
		return 0
	if len(entries) != 1:
		sys.exit(f"{path}: expected one icon group, found {len(entries)}")
	blob = struct.pack("<H", len(WANT)) + WANT.encode("utf-16-le")
	at = (max(vsize, res_size) + 3) & ~3
	if at + len(blob) > raw_size:
		sys.exit(f"{path}: no room in .rsrc for the name")
	data[base + at:base + at + len(blob)] = blob
	struct.pack_into("<I", data, entries[0], 0x80000000 | at)
	# Named entries come before id entries; with a single entry it just moves to the named count.
	struct.pack_into("<HH", data, base + group_dir + 12, 1, 0)
	new_size = at + len(blob)
	struct.pack_into("<I", data, sec_hdr + 8, max(vsize, new_size))
	struct.pack_into("<I", data, res_dir_at + 4, max(res_size, new_size))
	struct.pack_into("<I", data, checksum_at, pe_checksum(data, checksum_at))
	with open(path, "wb") as f:
		f.write(data)
	print(f"{path}: icon group renamed {current!r} -> {WANT}")
	return 0


def pe_checksum(data: bytearray, checksum_at: int) -> int:
	size = len(data)
	padded = bytes(data) + b"\0" * (size % 2)
	total = sum(memoryview(padded).cast("H"))
	# Leave out the checksum field itself.
	total -= struct.unpack_from("<H", data, checksum_at)[0] + struct.unpack_from("<H", data, checksum_at + 2)[0]
	while total >> 16:
		total = (total & 0xFFFF) + (total >> 16)
	return (total + size) & 0xFFFFFFFF


if __name__ == "__main__":
	if len(sys.argv) != 2:
		sys.exit(__doc__)
	sys.exit(main(sys.argv[1]))
