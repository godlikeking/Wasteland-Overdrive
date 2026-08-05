extends CanvasLayer
## Pause screen. Owns the ESC key, and doubles as the run's inventory sheet:
## every weapon with its level and how close it is to a merge, plus the passive
## cards taken so far.
##
## ESC ownership lives here rather than on the Game root deliberately. `Game` is
## a PAUSABLE node and has to stay that way — World / Player / SpawnDirector all
## inherit their process mode from it and must stop when the game pauses — but
## that also meant `Game._unhandled_input` went silent the moment `paused` became
## true, so the toggle could pause the game and never resume it. This node runs
## with PROCESS_MODE_ALWAYS, so it can always hear the key that un-pauses.

@onready var weapon_header: Label = $CenterContainer/Panel/MarginContainer/VBox/Columns/WeaponColumn/WeaponHeader
@onready var weapon_list: VBoxContainer = $CenterContainer/Panel/MarginContainer/VBox/Columns/WeaponColumn/WeaponList
@onready var passive_list: VBoxContainer = $CenterContainer/Panel/MarginContainer/VBox/Columns/PassiveColumn/PassiveList
@onready var resume_button: Button = $CenterContainer/Panel/MarginContainer/VBox/ResumeButton

const DIM: Color = Color(0.62, 0.62, 0.68)
const GOLD: Color = Color(1.0, 0.85, 0.4)
const GREEN: Color = Color(0.6, 0.9, 0.7)
const ROW_FONT: int = 15

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	resume_button.pressed.connect(close)

func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("pause"):
		return
	if visible:
		close()
	elif not get_tree().paused:
		open()
	else:
		# Paused, but not by us: LevelUp / GameOver / Shop is holding a modal
		# panel open. Resuming here would un-pause the game underneath it, so
		# leave the key alone (and unhandled, in case they want it later).
		return
	get_viewport().set_input_as_handled()

## Show the panel and pause the run. Contents are rebuilt on every open so the
## sheet always reflects the arsenal as of this moment.
func open() -> void:
	_build_weapons()
	_build_passives()
	visible = true
	get_tree().paused = true

func close() -> void:
	visible = false
	get_tree().paused = false

func _build_weapons() -> void:
	_clear(weapon_list)
	var slots: int = WeaponDirector.slots_used()
	weapon_header.text = "武器 %d／%d" % [slots, WeaponDirector.MAX_WEAPONS]
	var groups: Array[Dictionary] = WeaponDirector.inventory_groups()
	if groups.is_empty():
		weapon_list.add_child(_row("（暂无武器）", "", DIM, DIM))
		return
	for g in groups:
		var level: int = int(g["level"])
		var count: int = int(g["count"])
		var left: String = "%s Lv%d" % [g["name"], level]
		if count > 1:
			left += " ×%d" % count
		weapon_list.add_child(_row(left, _merge_note(level, int(g["max_level"]), count), GOLD, DIM))

## Right-hand hint describing this row's merge progress. Merging is automatic and
## takes MERGE_COUNT copies at once, so a row is only ever 1 or 2 copies deep —
## which is exactly why the counts are worth showing.
func _merge_note(level: int, max_level: int, count: int) -> String:
	if level >= max_level:
		return "已满级"
	var need: int = WeaponDirector.MERGE_COUNT - count
	if need <= 0:
		# Merging is automatic, so this should be unreachable. Say so rather than
		# printing "还差 0 把", which would read like a stuck upgrade.
		return "可合并"
	return "还差 %d 把升 Lv%d" % [need, level + 1]

func _build_passives() -> void:
	_clear(passive_list)
	var taken: Dictionary = GameState.taken_upgrades
	if taken.is_empty():
		passive_list.add_child(_row("（暂无强化）", "", DIM, DIM))
		return
	# Insertion-ordered, so this lists the picks in the order they were chosen.
	for id in taken.keys():
		var n: int = int(taken[id])
		var right: String = "×%d" % n if n > 1 else ""
		passive_list.add_child(_row(UpgradeDB.name_of(String(id)), right, GREEN, DIM))

## One inventory line: label on the left, note pushed to the right edge.
func _row(left: String, right: String, left_color: Color, right_color: Color) -> HBoxContainer:
	var row := HBoxContainer.new()
	var name_label := Label.new()
	name_label.text = left
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.add_theme_font_size_override("font_size", ROW_FONT)
	name_label.add_theme_color_override("font_color", left_color)
	row.add_child(name_label)
	if right != "":
		var note := Label.new()
		note.text = right
		note.add_theme_font_size_override("font_size", ROW_FONT - 2)
		note.add_theme_color_override("font_color", right_color)
		row.add_child(note)
	return row

## `free()` rather than `queue_free()`: the tree is paused while this panel is
## up, but more importantly the rows must be gone *before* the rebuild adds new
## ones, or a reopen would show the previous contents stacked on top.
func _clear(list: VBoxContainer) -> void:
	for c in list.get_children():
		list.remove_child(c)
		c.free()
