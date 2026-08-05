extends Node2D
## Dev-only self test for the pause screen. Not referenced by the game; run it
## headless:
##
##   godot --headless res://scenes/dev/pause_selftest.tscn
##
## Exits with code 0 on success, 1 if any assertion failed.
##
## The headline case is the resume bug: ESC used to pause the run and then go
## deaf, because the handler lived on the PAUSABLE Game root. So the ESC tests
## drive real InputEventActions through the viewport rather than calling the
## handler directly — a direct call would pass even with the old wiring, since
## the bug was about the event never arriving.
##
## The rest checks the panel's contents: per-weapon level, merge progress, and
## the passive-card list.

@onready var _player: Node2D = $Player
@onready var _menu: CanvasLayer = $PauseMenu

var _failures: int = 0

func _ready() -> void:
	await get_tree().process_frame
	print("=== pause selftest ===")
	await _test_esc_opens()
	await _test_esc_resumes()
	await _test_esc_ignored_when_another_panel_owns_pause()
	await _test_resume_button()
	await _test_weapon_rows_show_level_and_merge_progress()
	await _test_merged_weapon_shows_new_level()
	await _test_passive_list()
	await _test_empty_state()
	await _test_reset_clears_passives()
	print("=== pause selftest failures: %d ===" % _failures)
	get_tree().quit(1 if _failures > 0 else 0)

# --- ESC ownership --------------------------------------------------------

func _test_esc_opens() -> void:
	var t: String = "esc_opens"
	await _reset_all()
	await _press_pause()
	if not _menu.visible:
		_fail(t, "panel still hidden after ESC")
		return
	if not get_tree().paused:
		_fail(t, "panel opened but the tree is not paused")
		return
	_ok(t, "ESC showed the panel and paused the run")

func _test_esc_resumes() -> void:
	# The reported bug: pausing worked, resuming did not.
	var t: String = "esc_resumes"
	await _reset_all()
	await _press_pause()
	if not get_tree().paused:
		_fail(t, "setup failed — first ESC did not pause")
		return
	await _press_pause()
	if get_tree().paused:
		_fail(t, "still paused after a second ESC — the resume key is not reaching the handler")
		return
	if _menu.visible:
		_fail(t, "unpaused but the panel is still on screen")
		return
	_ok(t, "second ESC resumed the run and hid the panel")

func _test_esc_ignored_when_another_panel_owns_pause() -> void:
	# LevelUp / GameOver / Shop pause the tree themselves. ESC must not resume
	# the game out from under their modal panels.
	var t: String = "esc_defers"
	await _reset_all()
	get_tree().paused = true
	await _press_pause()
	if _menu.visible:
		_fail(t, "opened on top of another panel's pause")
		get_tree().paused = false
		return
	if not get_tree().paused:
		_fail(t, "ESC resumed a run that another panel had paused")
		return
	get_tree().paused = false
	_ok(t, "ESC left another panel's pause alone")

func _test_resume_button() -> void:
	var t: String = "resume_button"
	await _reset_all()
	await _press_pause()
	var btn: Button = _menu.resume_button
	btn.pressed.emit()
	await get_tree().process_frame
	if get_tree().paused or _menu.visible:
		_fail(t, "continue button left paused=%s visible=%s" % [get_tree().paused, _menu.visible])
		return
	_ok(t, "continue button resumed the run")

# --- panel contents -------------------------------------------------------

func _test_weapon_rows_show_level_and_merge_progress() -> void:
	var t: String = "merge_progress"
	await _reset_all()
	# Two of one weapon (one away from a merge) and one of another (two away).
	WeaponDirector.add_weapon_by_id("bullet_volley")
	WeaponDirector.add_weapon_by_id("bullet_volley")
	WeaponDirector.add_weapon_by_id("shotgun")
	await _advance(0.1)
	if WeaponDirector.slots_used() != 3:
		_fail(t, "setup holds %d weapons, want 3" % WeaponDirector.slots_used())
		return
	_menu.open()
	var rows: Array[String] = _rows(_menu.weapon_list)
	if rows.size() != 2:
		_fail(t, "%d weapon rows for 3 weapons in 2 (id, level) groups: %s" % [rows.size(), rows])
		_menu.close()
		return
	var pair: String = _find_row(rows, WeaponDirector.display_name_of("bullet_volley"))
	if not pair.contains("Lv1") or not pair.contains("×2"):
		_fail(t, "the doubled weapon reads '%s', want its level and ×2" % pair)
		_menu.close()
		return
	if not pair.contains("还差 1 把"):
		_fail(t, "2 copies read '%s', want '还差 1 把'" % pair)
		_menu.close()
		return
	var single: String = _find_row(rows, WeaponDirector.display_name_of("shotgun"))
	if not single.contains("还差 2 把"):
		_fail(t, "1 copy reads '%s', want '还差 2 把'" % single)
		_menu.close()
		return
	if single.contains("×"):
		_fail(t, "a lone copy reads '%s', want no count suffix" % single)
		_menu.close()
		return
	_menu.close()
	_ok(t, "rows show level, copy count and how many more a merge needs")

func _test_merged_weapon_shows_new_level() -> void:
	var t: String = "merged_level"
	await _reset_all()
	for i in range(3):
		WeaponDirector.add_weapon_by_id("bullet_volley")
	await _advance(0.1)
	if WeaponDirector.weapon_level_of("bullet_volley") != 2:
		_fail(t, "setup did not merge (level %d)" % WeaponDirector.weapon_level_of("bullet_volley"))
		return
	_menu.open()
	var rows: Array[String] = _rows(_menu.weapon_list)
	var row: String = _find_row(rows, WeaponDirector.display_name_of("bullet_volley"))
	if not row.contains("Lv2"):
		_fail(t, "after a merge the row reads '%s', want Lv2" % row)
		_menu.close()
		return
	if row.contains("×"):
		_fail(t, "the merged survivor reads '%s', want a single copy" % row)
		_menu.close()
		return
	# 12 catalog slots but only 1 weapon left, so the header must show the drop.
	if not _menu.weapon_header.text.contains("1"):
		_fail(t, "header reads '%s', want 1 slot used" % _menu.weapon_header.text)
		_menu.close()
		return
	_menu.close()
	_ok(t, "the merged survivor shows its new level and a single copy")

func _test_passive_list() -> void:
	var t: String = "passives"
	await _reset_all()
	GameState.record_upgrade("damage_up")
	GameState.record_upgrade("damage_up")
	GameState.record_upgrade("range_up")
	_menu.open()
	var rows: Array[String] = _rows(_menu.passive_list)
	if rows.size() != 2:
		_fail(t, "%d passive rows for 2 distinct cards: %s" % [rows.size(), rows])
		_menu.close()
		return
	var stacked: String = _find_row(rows, UpgradeDB.name_of("damage_up"))
	if not stacked.contains("×2"):
		_fail(t, "a twice-taken card reads '%s', want ×2" % stacked)
		_menu.close()
		return
	var once: String = _find_row(rows, UpgradeDB.name_of("range_up"))
	if once.contains("×"):
		_fail(t, "a once-taken card reads '%s', want no count suffix" % once)
		_menu.close()
		return
	# Insertion order, so the first pick is listed first.
	if not rows[0].contains(UpgradeDB.name_of("damage_up")):
		_fail(t, "rows are %s, want the first pick listed first" % [rows])
		_menu.close()
		return
	_menu.close()
	_ok(t, "passive cards are listed in pick order with their stack counts")

func _test_empty_state() -> void:
	var t: String = "empty"
	await _reset_all()
	_menu.open()
	var weapons: Array[String] = _rows(_menu.weapon_list)
	var passives: Array[String] = _rows(_menu.passive_list)
	if weapons.size() != 1 or not weapons[0].contains("暂无"):
		_fail(t, "an empty arsenal renders %s, want one placeholder row" % [weapons])
		_menu.close()
		return
	if passives.size() != 1 or not passives[0].contains("暂无"):
		_fail(t, "an empty passive list renders %s, want one placeholder row" % [passives])
		_menu.close()
		return
	# Reopening must not stack the old rows under the new ones.
	_menu.close()
	_menu.open()
	if _rows(_menu.weapon_list).size() != 1:
		_fail(t, "reopening left %d rows, want 1 — the rebuild is not clearing" % _rows(_menu.weapon_list).size())
		_menu.close()
		return
	_menu.close()
	_ok(t, "empty columns show a placeholder and reopening rebuilds cleanly")

func _test_reset_clears_passives() -> void:
	var t: String = "reset"
	await _reset_all()
	GameState.record_upgrade("damage_up")
	GameState.reset()
	if not GameState.taken_upgrades.is_empty():
		_fail(t, "taken_upgrades survived reset(): %s" % [GameState.taken_upgrades])
		return
	_ok(t, "a new run starts with an empty passive ledger")

# --- helpers --------------------------------------------------------------

## Drive a real "pause" action through the viewport, the same route a keypress
## takes, and give the handler a frame to run.
func _press_pause() -> void:
	var ev := InputEventAction.new()
	ev.action = "pause"
	ev.pressed = true
	get_tree().root.push_input(ev)
	await get_tree().process_frame

## Visible text of each row, flattened to one string per row.
func _rows(list: VBoxContainer) -> Array[String]:
	var out: Array[String] = []
	for row in list.get_children():
		var parts: Array[String] = []
		for label in row.get_children():
			if label is Label:
				parts.append((label as Label).text)
		out.append(" ".join(parts))
	return out

## The one row mentioning `needle`, or "" — reported as-is so a failure message
## shows what was actually rendered.
func _find_row(rows: Array[String], needle: String) -> String:
	for r in rows:
		if r.contains(needle):
			return r
	return ""

func _reset_all() -> void:
	_menu.visible = false
	get_tree().paused = false
	GameState.reset()
	WeaponDirector._reset()
	for c in _player.get_children():
		if c is BaseWeapon:
			c.queue_free()
	await _advance(0.1)

func _advance(seconds: float) -> void:
	var t: float = 0.0
	while t < seconds:
		await get_tree().process_frame
		t += get_process_delta_time()

func _ok(test_name: String, msg: String) -> void:
	print("  OK   %-22s %s" % [test_name, msg])

func _fail(test_name: String, msg: String) -> void:
	_failures += 1
	printerr("  FAIL %-22s %s" % [test_name, msg])
