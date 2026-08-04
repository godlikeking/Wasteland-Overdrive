extends Node2D
## Dev-only self test for the on-body weapon mounts. Not referenced by the game;
## run it headless:
##
##   godot --headless res://scenes/dev/weapon_mount_selftest.tscn
##
## Exits with code 0 on success, 1 if any assertion failed.
##
## Weapons are granted through the real WeaponDirector (not hand-instanced) so
## the test also covers the path WeaponMounts actually depends on: the director
## add_child()ing weapons onto the player, and fusion queue_free()ing the base
## weapons in the same frame it adds the fused one.

@onready var _player: Node2D = $Player

var _mounts: Node2D = null
var _failures: int = 0

## Minimal stand-in for Enemy — WeaponMounts only ever asks for its position.
class FakeEnemy extends Node2D:
	func _ready() -> void:
		add_to_group("enemies")

	func take_damage(_amount: float, _hit_dir: Vector2 = Vector2.ZERO) -> void:
		pass

func _ready() -> void:
	await get_tree().process_frame
	print("=== weapon mount selftest ===")
	_mounts = _player.get_node_or_null("WeaponMounts") as Node2D
	if _mounts == null:
		printerr("  FAIL %-22s Player has no WeaponMounts child" % "mounts_exist")
		print("=== weapon mount selftest failures: 1 ===")
		get_tree().quit(1)
		return
	_ok("mounts_exist", "WeaponMounts found under Player")

	await _test_layout_grows_with_arsenal()
	await _test_duplicate_weapons_get_distinct_mounts()
	await _test_placeholder_geometry()
	await _test_icon_texture_source()
	await _test_aim_follows_target()
	await _test_keeps_angle_without_target()
	await _test_finishes_turn_after_target_dies()
	await _test_fusion_resyncs_mounts()
	await _test_rebuild_skips_freed_weapon()
	await _test_full_arsenal_layout()
	print("=== weapon mount selftest failures: %d ===" % _failures)
	get_tree().quit(1 if _failures > 0 else 0)

# --- layout --------------------------------------------------------------

## Mount offsets must be re-picked every time the arsenal size changes, so a
## lone weapon is centred and a pair is symmetric.
func _test_layout_grows_with_arsenal() -> void:
	var t: String = "layout"
	await _grant("bullet_volley")
	if not _check_slots(t, 1):
		return
	await _grant("chain_lightning")
	if not _check_slots(t, 2):
		return
	await _grant("orbiting_blades")
	if not _check_slots(t, 3):
		return
	var ids: Array[String] = _mounts.mounted_ids()
	var want_ids: Array = ["bullet_volley", "chain_lightning", "orbiting_blades"]
	if Array(ids) != want_ids:
		_fail(t, "mounted %s, want %s" % [ids, want_ids])
		return
	_ok(t, "1 -> shoulder, 2 -> symmetric hips, 3 -> hips + shoulder")

## Several copies of the same weapon must each get their own mount icon at a
## distinct position, and the rebuild must keep their angles per-instance
## (the kept dict is keyed by instance id, not config id). Two copies coexist
## (three would merge into one Lv2, so two is the max non-merged same-id case).
func _test_duplicate_weapons_get_distinct_mounts() -> void:
	var t: String = "duplicates"
	await _clear_arsenal()
	WeaponDirector.add_weapon_by_id("shotgun")
	WeaponDirector.add_weapon_by_id("shotgun")
	await get_tree().process_frame
	await get_tree().process_frame
	if _mounts.icon_count() != 2:
		_fail(t, "%d icons for 2 shotgun copies, want 2" % _mounts.icon_count())
		return
	var ids: Array[String] = _mounts.mounted_ids()
	for id in ids:
		if id != "shotgun":
			_fail(t, "mounted %s, want all shotgun" % id)
			return
	var icons: Array[Sprite2D] = _mounts.icons()
	if icons[0].position.is_equal_approx(icons[1].position):
		_fail(t, "two shotgun icons stacked at %s" % icons[0].position)
		return
	_ok(t, "2 copies of shotgun mount at 2 distinct positions (%s, %s)" % [
		icons[0].position, icons[1].position])
	# Restore the 3-weapon arsenal that the following tests (aim_follows,
	# finishes_turn, fusion_resync) expect from _test_layout_grows_with_arsenal.
	# Shotgun's 260px range would also leave the 300px-away test enemy out of
	# range, so a leaked duplicate pair would silently break every later check.
	await _clear_arsenal()
	for id in ["bullet_volley", "chain_lightning", "orbiting_blades"]:
		WeaponDirector.add_weapon_by_id(id)
	await get_tree().process_frame
	await get_tree().process_frame

func _check_slots(t: String, n: int) -> bool:
	if _mounts.icon_count() != n:
		_fail(t, "%d weapon(s) held but %d icon(s) mounted" % [n, _mounts.icon_count()])
		return false
	var want: Array = _mounts.MOUNT_LAYOUTS[n]
	var icons: Array[Sprite2D] = _mounts.icons()
	for i in range(n):
		if not icons[i].position.is_equal_approx(want[i]):
			_fail(t, "icon %d of %d at %s, want %s" % [i, n, icons[i].position, want[i]])
			return false
	return true

## Verify that every icon's texture matches its source and its pivot sits
## at the grip so rotating it swings the barrel out toward the target.
## When config.icon is null the generated placeholder is sized from icon_size;
## when it carries real art the art's own dimensions win.
func _test_placeholder_geometry() -> void:
	var t: String = "placeholder_geometry"
	var icons: Array[Sprite2D] = _mounts.icons()
	var ids: Array[String] = _mounts.mounted_ids()
	for i in range(icons.size()):
		var icon: Sprite2D = icons[i]
		var cfg: WeaponConfig = _config_for(ids[i])
		if icon.texture == null:
			_fail(t, "%s icon has no texture" % ids[i])
			return
		var expected_w: int
		var expected_offset: float
		if cfg.icon:
			expected_w = int(cfg.icon.get_size().x)
			expected_offset = cfg.icon.get_size().x * 0.5
		else:
			expected_w = int(cfg.icon_size.x)
			expected_offset = cfg.icon_size.x * 0.5
		if icon.texture.get_width() != expected_w:
			_fail(t, "%s icon is %dx%d, expected width %d (cfg.icon=%s)" % [
				ids[i], icon.texture.get_width(), icon.texture.get_height(),
				expected_w, "yes" if cfg.icon else "no"])
			return
		if not is_equal_approx(icon.offset.x, expected_offset):
			_fail(t, "%s icon offset.x=%.1f, want %.1f (half its length)" % [
				ids[i], icon.offset.x, expected_offset])
			return
	_ok(t, "%d icons sized from config, pivoted at the grip" % icons.size())

## Real artwork must win over the generated placeholder, so dropping a PNG into
## a .tres is all it takes to replace the stand-in. Also checks the shipped
## config really carries art now, otherwise this would silently pass forever
## if someone unhooked the PNGs.
func _test_icon_texture_source() -> void:
	var t: String = "icon_source"
	var cfg: WeaponConfig = _config_for("bullet_volley")
	if cfg == null:
		_fail(t, "could not load bullet_volley config")
		return
	var shipped: Texture2D = cfg.icon
	if shipped == null:
		_fail(t, "bullet_volley.tres has no icon; the mount art is unhooked")
		return

	cfg.icon = null
	var placeholder: Sprite2D = _mounts._make_icon(cfg)
	var was_placeholder: bool = placeholder.texture is GradientTexture2D
	placeholder.free()

	var img: Image = Image.create(7, 3, false, Image.FORMAT_RGBA8)
	img.fill(Color.WHITE)
	var real: ImageTexture = ImageTexture.create_from_image(img)
	cfg.icon = real
	var custom: Sprite2D = _mounts._make_icon(cfg)
	var used_real: bool = custom.texture == real
	# Art dimensions, not icon_size, must drive the pivot.
	var pivot_from_art: bool = is_equal_approx(custom.offset.x, 3.5)
	custom.free()
	cfg.icon = shipped   # leave the shared resource as we found it

	if not was_placeholder:
		_fail(t, "a config with icon=null did not get a GradientTexture2D placeholder")
	elif not used_real:
		_fail(t, "config.icon was ignored, placeholder used instead")
	elif not pivot_from_art:
		_fail(t, "offset.x=%.1f, want 3.5 (half the 7px art, not icon_size)" % custom.offset.x)
	else:
		_ok(t, "icon=null -> placeholder, icon=Texture2D -> that texture, pivot from art")

# --- aiming --------------------------------------------------------------

## Icons must turn toward the nearest enemy. Deliberately starts with a target
## that is NOT at angle 0, otherwise a broken implementation that never rotates
## would pass by accident.
func _test_aim_follows_target() -> void:
	var t: String = "aim_follows"
	var e := FakeEnemy.new()
	add_child(e)
	e.global_position = _player.global_position + Vector2(0, 300)   # straight down
	await _wait(0.6)
	if not _all_icons_face(t, PI * 0.5, "below the player"):
		_clear_enemies()
		return
	e.global_position = _player.global_position + Vector2(-300, 0)  # to the left
	await _wait(0.6)
	if not _all_icons_face(t, PI, "to the left"):
		_clear_enemies()
		return
	_ok(t, "swung to +Y then to -X")
	_clear_enemies()

func _all_icons_face(t: String, want: float, where: String) -> bool:
	var icons: Array[Sprite2D] = _mounts.icons()
	if icons.is_empty():
		_fail(t, "no icons to check")
		return false
	for i in range(icons.size()):
		var off: float = absf(angle_difference(icons[i].rotation, want))
		if off > 0.15:
			_fail(t, "icon %d off by %.2f rad with the enemy %s" % [i, off, where])
			return false
	return true

## Losing every target must not yank the icons back to angle 0.
func _test_keeps_angle_without_target() -> void:
	var t: String = "keeps_angle"
	var e := FakeEnemy.new()
	add_child(e)
	e.global_position = _player.global_position + Vector2(0, -300)   # straight up
	await _wait(0.6)
	var before: Array[float] = []
	for icon in _mounts.icons():
		before.append(icon.rotation)
	if before.is_empty():
		_fail(t, "no icons to check")
		return
	_clear_enemies()
	await _wait(0.3)
	var icons: Array[Sprite2D] = _mounts.icons()
	for i in range(icons.size()):
		var drift: float = absf(angle_difference(icons[i].rotation, before[i]))
		if drift > 0.05:
			_fail(t, "icon %d drifted %.2f rad after the enemy died" % [i, drift])
			return
	_ok(t, "held the last aim (%.2f rad) with no enemies left" % before[0])

## Mid-turn loss of target must still let the icon finish its swing. This
## catches the bug where aim == Vector2.ZERO overwrites _aims[i] and the
## icon then freezes mid-rotation because the early-return in _process skips
## the lerp when _aims[i] == ZERO.
func _test_finishes_turn_after_target_dies() -> void:
	var t: String = "finishes_turn"
	var e := FakeEnemy.new()
	add_child(e)
	e.global_position = _player.global_position + Vector2(300, 0)    # right
	await _wait(0.6)
	# Now start a turn toward the left, but kill the enemy mid-way.
	e.global_position = _player.global_position + Vector2(-300, 0)   # left
	await _wait(0.09)  # short enough to be mid-turn, > aim refresh
	_clear_enemies()
	await _wait(0.5)
	var icons: Array[Sprite2D] = _mounts.icons()
	for i in range(icons.size()):
		var off: float = absf(angle_difference(icons[i].rotation, PI))
		if off > 0.2:
			_fail(t, "icon %d off by %.2f rad after the target died mid-turn" % [i, off])
			return
	_ok(t, "%d icons completed the turn after target vanished" % icons.size())

# --- fusion --------------------------------------------------------------

## Fusion frees the base weapons and adds the fused one in the same frame, so
## the mounts have to end up with exactly one icon.
func _test_fusion_resyncs_mounts() -> void:
	var t: String = "fusion_resync"
	if _mounts.icon_count() != 3:
		_fail(t, "expected 3 icons before fusing, got %d" % _mounts.icon_count())
		return
	WeaponDirector._debug_max_base_weapons()
	var new_id: String = WeaponDirector.fuse("apocalypse")
	if new_id != "apocalypse":
		_fail(t, "fuse() returned %s" % [new_id if new_id != "" else "\"\""])
		return
	await get_tree().process_frame
	await get_tree().process_frame
	var ids: Array[String] = _mounts.mounted_ids()
	if _mounts.icon_count() != 1:
		_fail(t, "%d icons left after fusing 3 weapons into 1" % _mounts.icon_count())
	elif Array(ids) != ["apocalypse"]:
		_fail(t, "mounted %s after fusion, want [apocalypse]" % [ids])
	elif not _mounts.icons()[0].position.is_equal_approx(_mounts.MOUNT_LAYOUTS[1][0]):
		_fail(t, "lone fused icon at %s, want the 1-weapon slot %s" % [
			_mounts.icons()[0].position, _mounts.MOUNT_LAYOUTS[1][0]])
	else:
		_ok(t, "3 base icons collapsed into 1 apocalypse icon on the shoulder")

## A weapon that is queue_free()d but has not left the tree yet must already be
## treated as gone. _process can run in that window — fusion frees the base
## weapons and adds the fused one within a single frame — so rebuilding without
## the is_queued_for_deletion() filter would mount an icon for a dead weapon.
## Rebuilt synchronously here, with no await, to sit squarely in that window.
func _test_rebuild_skips_freed_weapon() -> void:
	var t: String = "skips_freed"
	var before: int = _mounts.icon_count()
	if before < 1:
		_fail(t, "no weapon left to free")
		return
	var doomed: Node = null
	for c in _player.get_children():
		if c is BaseWeapon:
			doomed = c
			break
	if doomed == null:
		_fail(t, "no BaseWeapon found under the player")
		return
	doomed.queue_free()
	if not doomed.is_queued_for_deletion():
		_fail(t, "queue_free did not mark the weapon for deletion")
		return
	# Still in the tree at this point — the rebuild has to skip it anyway.
	_mounts._rebuild()
	if _mounts.icon_count() != before - 1:
		_fail(t, "freed weapon still mounted (%d icons, want %d)" % [_mounts.icon_count(), before - 1])
	else:
		_ok(t, "%d -> %d icons while the freed weapon was still in the tree" % [before, before - 1])

# --- full arsenal --------------------------------------------------------

## A maxed-out 12-weapon arsenal has to produce 12 distinct, readable icons.
## MOUNT_LAYOUTS only hand-tunes up to 6, so 7-12 fall through to the two-ring
## fallback, and this is the test that keeps that fallback from stacking icons
## on top of each other.
func _test_full_arsenal_layout() -> void:
	var t: String = "full_arsenal"
	await _clear_arsenal()
	for id in WeaponDirector.WEAPON_CATALOG.keys():
		WeaponDirector.add_weapon_by_id(String(id))
	# Fusions are only reachable through fuse(), which CONSUMES its ingredients
	# and so can never raise the count to 12. Added directly here because this
	# tests the layout at the cap, not the fusion rules.
	for fid in WeaponDirector.FUSION_RECIPES.keys():
		_force_add_fusion(String(fid))
	await get_tree().process_frame
	await get_tree().process_frame
	var want: int = WeaponDirector.MAX_WEAPONS
	if _mounts.icon_count() != want:
		_fail(t, "%d weapons equipped but %d icons mounted" % [
			WeaponDirector.slots_used(), _mounts.icon_count()])
		return
	_ok(t, "%d weapons -> %d icons" % [want, _mounts.icon_count()])

	# Icons all aim the same way, so they are parallel bars radiating from their
	# mount points: two of them read as one blob once their mount points sit
	# closer than the SHORTER icon's on-screen height (the shorter one gets fully
	# swallowed by the taller). Using the per-pair shorter height — not the
	# tallest icon in the whole set — is what matters, since the tallest gun
	# (apocalypse) sits alone at a column end and never brackets a neighbour.
	var icons: Array[Sprite2D] = _mounts.icons()
	var worst: float = INF
	var worst_pair: String = ""
	for i in range(icons.size()):
		for j in range(i + 1, icons.size()):
			if icons[i].texture == null or icons[j].texture == null:
				continue
			var limit: float = minf(
				icons[i].texture.get_height() * icons[i].scale.y,
				icons[j].texture.get_height() * icons[j].scale.y)
			var d: float = icons[i].position.distance_to(icons[j].position)
			if d < limit and d < worst:
				worst = d
				worst_pair = "%d/%d" % [i, j]
	if worst != INF:
		_fail(t, "icons %s only %.1fpx apart, under the shorter icon height" % [
			worst_pair, worst])
		return
	_ok(t, "every pair of %d icons is at least the shorter icon's height apart" % icons.size())

	# Icons must stay on the LEFT or RIGHT of the body (never front/back). The
	# two-column layout fixes x at ±SIDE_X, so every icon's |x| must be near
	# SIDE_X. Vertically the column may extend a little past the body (6 per
	# side), but it must stay roughly symmetric around the centre.
	var side: float = _mounts.SIDE_X
	var step: float = _mounts.SIDE_STEP
	var max_y: float = step * 6.0   # generous: 6-per-side column spread
	for icon in icons:
		if absf(absf(icon.position.x) - side) > 0.1:
			_fail(t, "icon at %s drifted off the side columns (|x| should be %.0f)" % [icon.position, side])
			return
		if absf(icon.position.y) > max_y:
			_fail(t, "an icon sits at %s, off the side column (|y| > %.0f)" % [icon.position, max_y])
			return
	_ok(t, "every one of %d icons sits on the left/right columns" % icons.size())

## Drop the whole arsenal, both the director's bookkeeping and the live nodes,
## so the next grant starts from an empty player.
func _clear_arsenal() -> void:
	WeaponDirector._reset()
	for c in _player.get_children():
		if c is BaseWeapon:
			c.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame

## Equip a fusion weapon without running fuse(). Recipes carry a config path but
## no scene path — the scene always lives at scenes/weapons/<id>.tscn.
func _force_add_fusion(id: String) -> void:
	var entry: Dictionary = WeaponDirector.FUSION_RECIPES.get(id, {})
	if entry.is_empty():
		return
	var cfg: Resource = ResourceLoader.load(String(entry.get("config", "")))
	var scene: PackedScene = ResourceLoader.load("res://scenes/weapons/%s.tscn" % id) as PackedScene
	if cfg is WeaponConfig and scene:
		WeaponDirector.add_weapon(cfg as WeaponConfig, scene)

# --- helpers -------------------------------------------------------------

func _grant(weapon_id: String) -> void:
	WeaponDirector.add_weapon_by_id(weapon_id)
	# The weapon enters the tree synchronously and marks the mounts dirty; the
	# rebuild lands on the next _process.
	await get_tree().process_frame
	await get_tree().process_frame

func _config_for(weapon_id: String) -> WeaponConfig:
	var path: String = "res://data/weapons/%s.tres" % weapon_id
	return ResourceLoader.load(path) as WeaponConfig

func _clear_enemies() -> void:
	for e in get_tree().get_nodes_in_group("enemies"):
		e.queue_free()

func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout

func _ok(test_name: String, msg: String) -> void:
	print("  OK   %-22s %s" % [test_name, msg])

func _fail(test_name: String, msg: String) -> void:
	_failures += 1
	printerr("  FAIL %-22s %s" % [test_name, msg])
