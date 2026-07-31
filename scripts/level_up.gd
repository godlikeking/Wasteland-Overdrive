extends CanvasLayer
## Level-up choice panel. Pauses the game, shows 3 random upgrade cards,
## applies the chosen one, then resumes.

signal choice_applied
signal fusion_chosen(recipe_id: String)
signal fusion_skipped

@onready var card_container: HBoxContainer = $CenterContainer/Panel/MarginContainer/VBox/CardRow
@onready var title_label: Label = $CenterContainer/Panel/MarginContainer/VBox/Title

var _card_scene := preload("res://scenes/ui/upgrade_card.tscn")
var _current_choices: Array = []
var _is_fusion: bool = false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false

func show_choices() -> void:
	# Clear previous cards
	for c in card_container.get_children():
		c.queue_free()
	_current_choices = UpgradeDB.roll(3)
	for up in _current_choices:
		var card := _card_scene.instantiate()
		card.setup(up)
		card.chosen.connect(_on_card_chosen.bind(up))
		card_container.add_child(card)
	_is_fusion = false
	if title_label:
		title_label.text = "等级提升 · 选择一项强化"
	visible = true
	get_tree().paused = true

## Shows N fusion cards (one per candidate recipe). Clicking picks the
## recipe, calling `fuse(recipe_id)` and emitting `fusion_chosen`.
func show_fusion_choices(candidates: Array) -> void:
	for c in card_container.get_children():
		c.queue_free()
	for cand in candidates:
		var card := _card_scene.instantiate()
		# Synthesize an Upgrade-like object so the card UI can display it.
		var fake: Dictionary = {
			"id": cand["id"],
			"name": cand["name"],
			"description": "融合：%s" % ", ".join(cand["recipe"]),
		}
		card.setup(fake)
		card.chosen.connect(_on_fusion_card_chosen.bind(cand["id"]))
		card_container.add_child(card)
	_is_fusion = true
	if title_label:
		title_label.text = "⚡ 装备融合 · 选择一个配方 ⚡"
	visible = true
	get_tree().paused = true

func _on_card_chosen(upgrade) -> void:
	if upgrade and upgrade.apply is Callable:
		upgrade.apply.call()
		GameState.upgrade_applied.emit(upgrade.id)
	visible = false
	get_tree().paused = false
	choice_applied.emit()

func _on_fusion_card_chosen(recipe_id: String) -> void:
	visible = false
	get_tree().paused = false
	fusion_chosen.emit(recipe_id)

## Player dismissed the fusion panel without picking. Continue the run.
func skip_fusion() -> void:
	visible = false
	get_tree().paused = false
	fusion_skipped.emit()
