extends CanvasLayer
## Level-up choice panel. Pauses the game, shows 3 random upgrade cards,
## applies the chosen one, then resumes.

signal choice_applied

@onready var card_container: HBoxContainer = $CenterContainer/Panel/MarginContainer/VBox/CardRow

var _card_scene := preload("res://scenes/ui/upgrade_card.tscn")
var _current_choices: Array = []

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
	visible = true
	get_tree().paused = true

func _on_card_chosen(upgrade) -> void:
	if upgrade and upgrade.apply is Callable:
		upgrade.apply.call()
		GameState.upgrade_applied.emit(upgrade.id)
	visible = false
	get_tree().paused = false
	choice_applied.emit()
