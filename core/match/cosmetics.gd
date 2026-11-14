class_name Cosmetics
extends RefCounted
## Player looks (§2.2, docs/GDD.md "Cosmetics shop"). The bean is the only body (the character
## skins were removed in 0.9.16); what players choose is its colour and an outfit.
## - The outfit (`PlayerState.outfit`): one piece per `CosmeticDef.OUTFIT_KINDS` slot (hat, shirt,
##   trousers, cape, boots, skin, eyes, mouth, beard), item ids from the shop or "" for none, on
##   the wire as one string per slot in that order (`sanitize_outfit`). Sent in the hello, changed with `set_outfit`. Any number of
##   beans may wear the same piece.
## - The slot colour (`PlayerState.color_index`, 0 .. SLOT_COLORS-1): one of the 8 colourblind-safe
##   colours, handed out by the server (first free), unique per player. It marks the player on the
##   HUD, the name tags and their ready pedestal.
## - The bean colour (`PlayerState.bean_color`, 0 .. COLOR_COUNT-1, `Palette.player_color`): what
##   the bean wears. The player's preferred colour from their profile (sent in the hello, changed
##   with the `set_color` intent from the pedestal's colour panel). Rule (`bean_color_for`): the
##   wish wins when no other bean wears it; else the slot colour; if even that is worn, the first
##   colour nobody wears. Two beans never share a colour.
## The server checks the index only: which colours a player owns lives in their local profile
## (`PlayerProfile`, no accounts), so the client offers owned colours only.

## Every bean colour: the 8 free ones, then the ones bought with Coins.
const COLOR_COUNT: int = 24
## The free colours the server hands out as slot colours.
const SLOT_COLORS: int = 8


static func is_valid_color(index: int) -> bool:
	return index >= 0 and index < COLOR_COUNT


static func is_slot_color(index: int) -> bool:
	return index >= 0 and index < SLOT_COLORS


## A clean outfit from anything a client sent: one id per `CosmeticDef.OUTFIT_KINDS` slot, in that order, each
## a shop item of that slot's kind or "" (unknown ids, wrong kinds and junk become "").
static func sanitize_outfit(v: Variant) -> PackedStringArray:
	var out := PackedStringArray()
	var src: Array = []
	if v is Array or v is PackedStringArray:
		src = Array(v)
	for i: int in CosmeticDef.OUTFIT_KINDS.size():
		var id: String = ""
		if i < src.size() and typeof(src[i]) in [TYPE_STRING, TYPE_STRING_NAME]:
			id = str(src[i])
		out.append(id if is_outfit_item(CosmeticDef.OUTFIT_KINDS[i], StringName(id)) else "")
	return out


## Whether `id` is a shop item of outfit slot `kind`.
static func is_outfit_item(kind: StringName, id: StringName) -> bool:
	if id == &"" or id.length() > Intents.NAME_MAX:
		return false
	var d: CosmeticDef = CosmeticShop.default().find(id)
	return d != null and d.kind == kind and kind in CosmeticDef.OUTFIT_KINDS


## The outfit as kind -> id (what `AvatarVisuals.set_outfit` takes), from a wire list.
static func outfit_dict(v: Variant) -> Dictionary:
	var clean: PackedStringArray = sanitize_outfit(v)
	var out: Dictionary = {}
	for i: int in clean.size():
		if clean[i] != "":
			out[CosmeticDef.OUTFIT_KINDS[i]] = StringName(clean[i])
	return out


## A player's outfit from their wire dictionary (`PlayerState.to_wire`).
static func outfit_of(p: Dictionary) -> Dictionary:
	return outfit_dict(p.get("outfit", []))


## The first slot colour not in `taken` (0 when all are).
static func free_slot(taken: Array[int]) -> int:
	for c: int in SLOT_COLORS:
		if not c in taken:
			return c
	return 0


## The bean colour a player gets: `wanted` when valid and no other bean wears it (`worn`), else
## their `slot` colour when free, else the first colour nobody wears.
static func bean_color_for(wanted: int, slot: int, worn: Array[int]) -> int:
	if is_valid_color(wanted) and not wanted in worn:
		return wanted
	if is_valid_color(slot) and not slot in worn:
		return slot
	for c: int in COLOR_COUNT:
		if not c in worn:
			return c
	return slot
