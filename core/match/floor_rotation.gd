class_name FloorRotation
extends RefCounted
## Which floor layout comes next (docs/FLOOR_PLAN.md), like the minigame bag (`MinigameDirector`):
## the layouts go into a shuffled bag; each casino round takes the next one, none comes twice
## before the bag is empty, and a fresh bag never starts with the layout that just stood. A layout
## that can't be used tonight (`usable` says no) is skipped and the next one is taken; when none
## can be used, the first layout (the full floor) stands. Pure and seeded: the server's floor RNG.

## Layout ids in rotation order, and the one that stands when none of them can (the full floor;
## the first id unless given).
var ids: Array[StringName] = []
var fallback: StringName = &""
var _rng: SeededRng
var _bag: Array[StringName] = []
var _last: StringName = &""


func _init(p_ids: Array[StringName], rng: SeededRng, p_fallback: StringName = &"") -> void:
	ids = p_ids.duplicate()
	_rng = rng
	fallback = p_fallback if p_fallback != &"" or ids.is_empty() else ids[0]


## The next layout id. `usable(id) -> bool` filters out the layouts that can't stand tonight.
func next(usable: Callable) -> StringName:
	var ok: Array[StringName] = []
	for id: StringName in ids:
		if usable.call(id):
			ok.append(id)
	if ok.is_empty():
		_last = fallback
		_bag.clear()
		return _last
	# Skipped layouts drop out of this bag.
	_bag = _bag.filter(func(id: StringName) -> bool: return id in ok)
	if _bag.is_empty():
		_bag = ok.duplicate()
		_rng.shuffle(_bag)
		# Never the same layout twice in a row across bag ends (unless it is the only one).
		if _bag.size() > 1 and _bag[0] == _last:
			var j: int = _rng.range_int(1, _bag.size() - 1)
			_bag[0] = _bag[j]
			_bag[j] = _last
	_last = _bag.pop_front()
	return _last


## The layout that stands now (&"" before the first `next`).
func current() -> StringName:
	return _last


## Layouts still in this bag, in the order they come.
func remaining() -> Array[StringName]:
	return _bag.duplicate()
