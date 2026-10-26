extends GutTest
## Number-key emotes (keys 4-7): the `play_emote {emote}` intent's schema, and the server checking
## the emote and showing it to everyone as `player_emote {player, emote}`.

var fx: ServerFixture


func after_each() -> void:
	if fx != null:
		fx.server.free()
		fx = null


func test_schema_needs_the_emote() -> void:
	assert_true(Intents.validate(Intents.make(&"play_emote", {"emote": &"thumbs_up"})).is_empty())
	assert_eq(Intents.validate(Intents.make(&"play_emote")), ["emote"] as Array[String])


func test_the_four_animated_emotes_in_key_order() -> void:
	assert_eq(Emotes.ANIMATED, [&"thumbs_up", &"thumbs_down", &"six_seven", &"default_dance"] as Array[StringName], "6-7 on the 6 key")
	for id: StringName in Emotes.ANIMATED:
		assert_true(Emotes.is_animated(id), String(id))
	assert_false(Emotes.is_animated(&"wave"), "the wheel's emotes are a separate list")
	assert_true(Emotes.has(&"six_seven"), "6-7 is on the wheel too")
	assert_eq(Emotes.LIST[0][0], &"six_seven", "at the top of the wheel")
	assert_eq(Emotes.bubble_text(&"six_seven"), "🤲 6-7")
	for row: Array in Emotes.LIST:
		assert_between(Emotes.length(row[0] as StringName), 2.0, Emotes.MAX_SECONDS, String(row[0]))
	for id: StringName in Emotes.ANIMATED:
		assert_between(Emotes.length(id), 2.0, Emotes.MAX_SECONDS, String(id))
	for i: int in 4:
		assert_true(InputMap.has_action(StringName("emote_%d" % (i + 1))), "emote_%d is an input action" % (i + 1))
		assert_true(Settings.KEYBINDS.has(StringName("emote_%d" % (i + 1))), "emote_%d can be remapped" % (i + 1))


func test_server_rebroadcasts_a_known_emote() -> void:
	fx = ServerFixture.new(2)
	fx.server.start_match()
	fx.run(3.1)
	var p: int = fx.player_ids[1]
	var r: Dictionary = fx.intent(p, &"play_emote", {"emote": &"default_dance"})
	assert_true(r["ok"], str(r))
	var shown: Array[Dictionary] = fx.of_type(&"player_emote")
	assert_eq(shown.size(), 1)
	assert_eq(int(shown[0]["player"]), p)
	assert_eq(shown[0]["emote"], &"default_dance")
	assert_true(Serializer.is_wire_safe(shown[0]))
	# Strings from the wire work too.
	assert_true(fx.intent(p, &"play_emote", {"emote": "six_seven"})["ok"])
	assert_eq(fx.of_type(&"player_emote")[1]["emote"], &"six_seven")


func test_server_rejects_unknown_emotes() -> void:
	fx = ServerFixture.new(2)
	fx.server.start_match()
	fx.run(3.1)
	var p: int = fx.player_ids[0]
	assert_eq(fx.intent(p, &"play_emote", {"emote": &"moonwalk"})["error"], &"unknown_emote")
	assert_eq(fx.intent(p, &"play_emote", {"emote": 4})["error"], &"unknown_emote")
	assert_eq(fx.server.submit_intent(p, {"type": &"play_emote"})["error"], &"malformed")
	assert_eq(fx.of_type(&"player_emote").size(), 0)
