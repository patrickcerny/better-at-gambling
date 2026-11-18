extends GutTest
## Security audit 2026-11-18: profile.cfg carries an HMAC signature (`PlayerProfile.signature`),
## so Coins, levels, unlocks and stats edited by hand are noticed and the edited file is not used.

const PATH: String = "user://test_profile_signature.cfg"


func before_each() -> void:
	for p: String in [PATH, PATH + ".tampered", PlayerProfile.seal_path(PATH)]:
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(p)


func after_each() -> void:
	before_each()


func _saved_profile() -> PlayerProfile:
	var p := PlayerProfile.new()
	p.coins = 1234
	p.xp = 500
	p.matches = 7
	p.wins = 3
	assert_eq(p.save(PATH), OK)
	return p


func _edit(find: String, replace: String) -> void:
	var text: String = FileAccess.get_file_as_string(PATH)
	assert_true(text.contains(find), "the file has %s" % find)
	var f: FileAccess = FileAccess.open(PATH, FileAccess.WRITE)
	f.store_string(text.replace(find, replace))
	f.close()


func test_a_saved_profile_loads_back_unchanged() -> void:
	_saved_profile()
	var q := PlayerProfile.new()
	assert_eq(q.load_from(PATH), OK)
	assert_eq(q.coins, 1234)
	assert_eq(q.xp, 500)
	assert_eq(q.matches, 7)
	assert_true(FileAccess.get_file_as_string(PATH).contains("[integrity]"))


func test_edited_coins_are_refused() -> void:
	_saved_profile()
	_edit("coins=1234", "coins=999999")
	var q := PlayerProfile.new()
	assert_eq(q.load_from(PATH), ERR_FILE_CORRUPT)
	assert_eq(q.coins, 0, "a fresh profile instead of the edited one")
	assert_true(FileAccess.file_exists(PATH + ".tampered"), "the edited file is kept for support")


func test_edited_unlocks_are_refused() -> void:
	_saved_profile()
	_edit("[stats]", "[rewards]\ncollected=PackedStringArray(\"skin_gold\")\n\n[stats]")
	assert_eq(PlayerProfile.new().load_from(PATH), ERR_FILE_CORRUPT)


func test_a_stripped_signature_is_refused_once_the_profile_was_signed() -> void:
	_saved_profile()
	var cfg := ConfigFile.new()
	cfg.load(PATH)
	cfg.set_value("profile", "coins", 999999)
	cfg.erase_section(PlayerProfile.SIGN_SECTION)
	cfg.save(PATH)
	assert_eq(PlayerProfile.new().load_from(PATH), ERR_FILE_CORRUPT)


func test_an_old_unsigned_profile_still_loads_and_gets_signed() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("profile", "coins", 300)
	cfg.save(PATH)  # written by 0.10.66 or older: no signature, no seal
	var q := PlayerProfile.new()
	assert_eq(q.load_from(PATH), OK)
	assert_eq(q.coins, 300)
	assert_eq(q.save(PATH), OK)
	assert_true(FileAccess.file_exists(PlayerProfile.seal_path(PATH)))
	assert_eq(PlayerProfile.new().load_from(PATH), OK, "signed from now on")


func test_a_changed_signature_is_refused() -> void:
	_saved_profile()
	var cfg := ConfigFile.new()
	cfg.load(PATH)
	cfg.set_value(PlayerProfile.SIGN_SECTION, "sig", "00".repeat(32))
	cfg.save(PATH)
	assert_eq(PlayerProfile.new().load_from(PATH), ERR_FILE_CORRUPT)
