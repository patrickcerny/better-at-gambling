extends Node
## `Audio` autoload: music crossfades and one-shot SFX on the right buses.
##
## M0 stub; implemented in M7.


## Sets a bus volume in linear 0..1 units. Unknown buses are ignored with a warning.
func set_bus_volume(bus_name: StringName, linear: float) -> void:
	var idx: int = AudioServer.get_bus_index(bus_name)
	if idx < 0:
		Log.warn(&"audio", "unknown bus %s" % bus_name)
		return
	AudioServer.set_bus_volume_db(idx, linear_to_db(clampf(linear, 0.0, 1.0)))
