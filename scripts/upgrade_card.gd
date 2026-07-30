extends PanelContainer
## Single upgrade card. Displays name + description and emits `chosen`
## when the button is pressed.

signal chosen

@onready var name_label: Label = $Margin/VBox/NameLabel
@onready var desc_label: Label = $Margin/VBox/DescLabel
@onready var button: Button = $Margin/VBox/PickButton

var upgrade

func _ready() -> void:
	button.pressed.connect(func(): chosen.emit())

func setup(p_upgrade) -> void:
	upgrade = p_upgrade
	# Node refs may not be ready yet if setup is called before add_child completes.
	# Defer to make sure @onready has run.
	call_deferred("_apply_labels")

func _apply_labels() -> void:
	if upgrade == null:
		return
	name_label.text = upgrade.name
	desc_label.text = upgrade.description
