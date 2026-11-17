extends GutTest
## Each other player's own voice volume and mute (Patrick 2026-11-16: "jeden spieler lautstärke
## einzeln einstellbar"): set in the settings panel's player list, applied on top of the distance,
## and remembered per Steam id across matches.

const STEAM_UID: String = "steam:76561190000000042"
const KEY: String = "steam_76561190000000042"

var ch: VoiceChannel
var heads: Dictionary[int, Node3D] = {}


func before_each() -> void:
	_forget()
	heads = {}
	for pid: int in [2, 3]:
		var h := Node3D.new()
		add_child_autofree(h)
		heads[pid] = h
	var state := ClientMatchState.new()
	state.players = {
		1: {"id": 1, "name": "Me", "uid": "steam:76561190000000001"},
		2: {"id": 2, "name": "Anna", "uid": STEAM_UID},
		3: {"id": 3, "name": "Lan Guy", "uid": "lan:abc"},
	}
	ch = VoiceChannel.new()
	ch.audio_enabled = false
	ch.setup(state, 1, func(pid: int) -> Node3D: return heads.get(pid, null), null, true)
	add_child_autofree(ch)


func after_each() -> void:
	_forget()
	VoiceChannel.current = null


func _forget() -> void:
	for what: String in ["volume", "mute"]:
		Settings.erase_value(VoiceChannel.PLAYERS_SECTION, "%s/%s" % [KEY, what])
	Settings.save()


func test_the_settings_key_is_the_steam_id_only() -> void:
	assert_eq(VoiceChannel.settings_key(STEAM_UID), KEY)
	assert_eq(VoiceChannel.settings_key("lan:abc"), "")
	assert_eq(VoiceChannel.settings_key("steam:notanumber"), "")
	assert_eq(VoiceChannel.settings_key(""), "")


func test_everyone_starts_at_normal_volume() -> void:
	assert_eq(ch.volume_of(2), 1.0)
	assert_eq(ch.volume_of(3), 1.0)
	assert_false(ch.is_muted(2))


func test_volume_is_clamped_and_reaches_the_playback() -> void:
	var pb: VoicePlayback = ch.playback_for(2)
	assert_not_null(pb)
	ch.set_volume(2, 5.0)
	assert_eq(ch.volume_of(2), VoiceChannel.MAX_PLAYER_VOLUME)
	assert_eq(pb.player_volume, VoiceChannel.MAX_PLAYER_VOLUME)
	ch.set_volume(2, -1.0)
	assert_eq(pb.player_volume, 0.0)
	ch.volumes[2] = 0.5
	ch._process(0.016)
	assert_eq(pb.player_volume, 0.5, "the channel keeps each playback on its player's volume")


func test_a_steam_players_volume_and_mute_are_remembered_for_the_next_match() -> void:
	ch.set_volume(2, 0.4)
	ch.set_muted(2, true)
	assert_almost_eq(float(Settings.get_value(VoiceChannel.PLAYERS_SECTION, KEY + "/volume", 1.0)), 0.4, 0.001)
	var later := VoiceChannel.new()
	later.audio_enabled = false
	later.setup(ch.state, 1, func(pid: int) -> Node3D: return heads.get(pid, null), null, true)
	add_child_autofree(later)
	assert_almost_eq(later.volume_of(2), 0.4, 0.001)
	assert_true(later.is_muted(2))
	later.set_volume(2, 1.0)
	later.set_muted(2, false)
	assert_false(Settings.has_value(VoiceChannel.PLAYERS_SECTION, KEY + "/volume"), "back to normal leaves nothing behind")
	assert_false(Settings.has_value(VoiceChannel.PLAYERS_SECTION, KEY + "/mute"))


func test_a_player_without_a_steam_id_is_only_set_for_this_match() -> void:
	ch.set_volume(3, 0.3)
	assert_almost_eq(ch.volume_of(3), 0.3, 0.001)
	assert_false(Settings.has_value(VoiceChannel.PLAYERS_SECTION, "/volume"))


func test_the_list_has_a_slider_and_mute_per_player() -> void:
	VoiceChannel.current = ch
	ch.set_volume(2, 1.5)
	var list := VoiceMuteList.new()
	add_child_autofree(list)
	assert_true(list.visible)
	assert_eq(list.rows.keys().size(), 2, "everyone but me")
	assert_false(list.rows.has(1))
	var s: HSlider = list.rows[2]["slider"]
	assert_eq(s.value, 1.5)
	assert_eq((list.rows[2]["value"] as Label).text, "150%")
	s.value = 0.25
	assert_almost_eq(ch.volume_of(2), 0.25, 0.001)
	assert_eq((list.rows[2]["value"] as Label).text, "25%")
	var b: Button = list.rows[3]["mute"]
	b.button_pressed = true
	assert_true(ch.is_muted(3))
	assert_false((list.rows[3]["slider"] as HSlider).editable, "a muted player's slider is greyed out")
