extends GutTest
## The hello a client sends must pass the server's `WireGuard`, which drops anything else without
## a word: with the outfit as a PackedStringArray (since 0.9.18) every join, hosted lobbies
## included, timed out with "The server did not answer." (Patrick on Steam 0.9.28).


func test_hello_with_the_worn_outfit_is_plain_wire_data() -> void:
	var looks: Dictionary = SceneRouter.profile_cosmetics()
	assert_true(looks["outfit"] is PackedStringArray, "the profile hands out a packed array")
	var hello: Dictionary = {"name": "Patrick", "uid": "steam:1", "color": int(looks["color"]), "outfit": looks["outfit"]}
	assert_false(WireGuard.is_clean_dictionary(hello), "raw, the guard refuses it")
	var wire: Dictionary = Net.wire_hello(hello)
	wire["protocol"] = Protocol.PROTOCOL_VERSION
	wire["build"] = Protocol.BUILD_ID
	assert_eq(WireGuard.problem(wire), "")
	assert_true(wire["outfit"] is Array)
	assert_eq((wire["outfit"] as Array).size(), (looks["outfit"] as PackedStringArray).size())
	assert_eq(Cosmetics.sanitize_outfit(wire["outfit"]), Cosmetics.sanitize_outfit(looks["outfit"]), "same pieces after the trip")
